/* Yeah — the behaviour of an Emacs frame.
 *
 * The page is a frame: it has a menu bar, a tab bar of open buffers, a header
 * line, a mode line that stays where the frame keeps it, and an echo area
 * that carries the minibuffer.  The keys are the keys Emacs binds.
 */

(function () {
  "use strict";

  var doc = document;
  var root = doc.documentElement;
  var body = doc.body;

  function $(selector, scope) { return (scope || doc).querySelector(selector); }
  function $$(selector, scope) {
    return Array.prototype.slice.call((scope || doc).querySelectorAll(selector));
  }
  function clamp(value, low, high) { return Math.min(high, Math.max(low, value)); }

  var content = $(".buffer__content");
  var echoArea = $(".echo-area");
  var minibuffer = $("#minibuffer");
  var minibufferPrompt = $("[data-minibuffer-prompt]");
  var messageEl = $("[data-message]");
  var frameModeLine = $(".mode-line--frame");
  var clockEl = frameModeLine ? $("[data-clock]", frameModeLine) : null;
  var positionEl = frameModeLine ? $("[data-position]", frameModeLine) : null;
  var lineEl = frameModeLine ? $("[data-line]", frameModeLine) : null;
  var modeEl = frameModeLine ? $("[data-mode]", frameModeLine) : null;
  var bufferNameEl = frameModeLine ? $("[data-buffer-name]", frameModeLine) : null;

  /* ---------------------------------------------------------------- *
   * The echo area speaks
   * ---------------------------------------------------------------- */

  var messageTimer = null;

  function say(text, tone) {
    if (!messageEl) { return; }
    messageEl.textContent = text || "";
    if (tone) { messageEl.setAttribute("data-tone", tone); }
    else { messageEl.removeAttribute("data-tone"); }
    if (messageTimer) { window.clearTimeout(messageTimer); }
    if (text) {
      messageTimer = window.setTimeout(function () {
        messageEl.textContent = "";
        messageEl.removeAttribute("data-tone");
      }, 4000);
    }
  }

  /* ---------------------------------------------------------------- *
   * 1. Themes — Emacs has themes, so the site has themes
   * ---------------------------------------------------------------- */

  var THEME_KEY = "yeah-theme";

  function themeLabel(name) { return name === "dark" ? "Emacs dark" : "Emacs default"; }

  function setTheme(name) {
    root.setAttribute("data-theme", name);
    $$("[data-theme-label]").forEach(function (el) { el.textContent = themeLabel(name); });
    try { window.localStorage.setItem(THEME_KEY, name); } catch (error) { /* private mode */ }
  }

  function currentTheme() { return root.getAttribute("data-theme") === "dark" ? "dark" : "light"; }

  function toggleTheme() {
    var next = currentTheme() === "dark" ? "light" : "dark";
    setTheme(next);
    say("Theme set to " + themeLabel(next));
  }

  setTheme(currentTheme());

  /* ---------------------------------------------------------------- *
   * 2. The menu bar
   * ---------------------------------------------------------------- */

  var menus = $$(".menu");

  function closeMenus(except) {
    menus.forEach(function (menu) {
      if (menu === except) { return; }
      menu.classList.remove("is-open");
      $(".menu__title", menu).setAttribute("aria-expanded", "false");
    });
  }

  function openMenu(menu) {
    closeMenus(menu);
    menu.classList.add("is-open");
    $(".menu__title", menu).setAttribute("aria-expanded", "true");
    placeMenu(menu);
  }

  /* The list of a menu hangs under its title.  It is fixed to the viewport,
     so the script has to say where it goes: the menu bar scrolls sideways
     on a narrow frame, and a list that stayed inside it would be cut off. */
  function placeMenu(menu) {
    var title = $(".menu__title", menu);
    var list = $(".menu__list", menu);
    if (!title || !list) { return; }
    var rect = title.getBoundingClientRect();
    var width = list.offsetWidth;
    var left = rect.left;
    if (left + width > window.innerWidth - 8) {
      left = Math.max(8, window.innerWidth - width - 8);
    }
    list.style.left = Math.round(left) + "px";
    list.style.top = Math.round(rect.bottom) + "px";
  }

  function placeOpenMenu() {
    var open = $(".menu.is-open");
    if (open) { placeMenu(open); }
  }

  function menuItems(menu) { return $$("a, button", $(".menu__list", menu)); }

  menus.forEach(function (menu) {
    var title = $(".menu__title", menu);

    title.addEventListener("click", function (event) {
      event.stopPropagation();
      if (menu.classList.contains("is-open")) { closeMenus(); }
      else { openMenu(menu); }
    });

    title.addEventListener("mouseenter", function () {
      if ($$(".menu.is-open").length) { openMenu(menu); }
    });

    menu.addEventListener("keydown", function (event) {
      var items = menuItems(menu);
      var index = items.indexOf(doc.activeElement);

      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        if (!menu.classList.contains("is-open")) { openMenu(menu); }
        var next = event.key === "ArrowDown"
          ? (index + 1) % items.length
          : (index - 1 + items.length) % items.length;
        items[next].focus();
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        closeMenus();
        title.focus();
        return;
      }

      if (event.key === "Tab") { closeMenus(); }
    });

    /* An item that points into the buffer moves the frame itself: the menu
       closes under the click, and a browser that finds the link hidden does
       not scroll to it. */
    $(".menu__list", menu).addEventListener("click", function (event) {
      var link = event.target.closest('a[href^="#"]');
      if (!link) { return; }
      event.preventDefault();
      closeMenus();
      goTo(link.getAttribute("href"));
    });
  });

  doc.addEventListener("click", function () { closeMenus(); });
  doc.addEventListener("keydown", function (event) {
    if (event.key === "Escape") { closeMenus(); }
  });

  /* The strip of the menu bar scrolls sideways on a narrow frame, and the
     window changes its size; the open list follows its title. */
  var menuStrip = $(".menus");
  if (menuStrip) {
    menuStrip.addEventListener("scroll", placeOpenMenu, { passive: true });
  }
  window.addEventListener("resize", placeOpenMenu);

  function openBuffersMenu() {
    var buffers = $('.menu[data-menu="buffers"]');
    if (!buffers) { return; }
    openMenu(buffers);
    $(".menu__title", buffers).focus();
  }

  /* ---------------------------------------------------------------- *
   * 3. Buffers: the sections of the page
   * ---------------------------------------------------------------- */

  var windows = $$(".buffer__content section[data-buffer]");
  var tabs = $$(".tab[data-target]");
  var activeBuffer = null;

  /* A tab names a buffer; the window that shows that buffer is the one it
     belongs to.  The names are the link — the anchor of a tab may point
     somewhere else (the first tab aims at the top of the buffer). */
  function bufferFor(name) {
    for (var i = 0; i < windows.length; i += 1) {
      if (windows[i].dataset.buffer === name) { return windows[i]; }
    }
    return null;
  }

  /* The buffers of the frame are the windows of the page, in the order the
     page shows them.  `switch-to-buffer' takes the name of one of them. */
  function bufferNames() {
    return windows.map(function (window) { return window.dataset.buffer; });
  }

  function goTo(target) {
    var element = target && target.charAt(0) === "#" ? $(target) : null;
    if (!element) { return; }
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, "", target);
    }
    var top = element.getBoundingClientRect().top + window.scrollY - chromeHeight();
    window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
  }

  /* The height of the bars that stay on top of the buffer.  A target that
     scrolls under them is a target the reader cannot see. */
  function chromeHeight() {
    var height = 0;
    [".menu-bar", ".tab-bar", ".header-line"].forEach(function (selector) {
      var element = $(selector);
      if (element) { height += element.getBoundingClientRect().height; }
    });
    return height + 16;
  }

  /* Only the strip of tabs moves sideways.  scrollIntoView would move the
     page as well, and that cancels the scroll the reader is watching. */
  function revealTab(tab) {
    var strip = tab.parentNode;
    if (!strip) { return; }
    var left = tab.offsetLeft - strip.offsetLeft;
    var right = left + tab.offsetWidth;
    if (left < strip.scrollLeft) { strip.scrollLeft = left; }
    else if (right > strip.scrollLeft + strip.clientWidth) {
      strip.scrollLeft = right - strip.clientWidth;
    }
  }

  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      goTo(tab.dataset.target);
      var buffer = bufferFor(tab.dataset.buffer);
      if (buffer) { setActiveBuffer(buffer); }
    });
  });

  function setActiveBuffer(buffer) {
    if (!buffer || buffer === activeBuffer) { return; }
    activeBuffer = buffer;

    tabs.forEach(function (tab) {
      var isActive = tab.dataset.buffer === buffer.dataset.buffer;
      tab.setAttribute("aria-selected", isActive ? "true" : "false");
      if (isActive) { revealTab(tab); }
    });

    if (frameModeLine) {
      if (bufferNameEl) { bufferNameEl.textContent = buffer.dataset.buffer || "*scratch*"; }
      if (modeEl) { modeEl.textContent = "(" + (buffer.dataset.mode || "Fundamental") + ")"; }
    }
  }

  /* The window that owns the top of the viewport is the selected one.
     At the very bottom of the buffer the last window cannot reach the top,
     so the reader is taken to be in it. */
  function currentWindow() {
    var last = windows[windows.length - 1];
    if (!last) { return null; }
    if (window.scrollY + window.innerHeight >= doc.documentElement.scrollHeight - 2) {
      return last;
    }
    var probe = window.scrollY + 140;
    var found = windows[0];
    for (var i = 0; i < windows.length; i += 1) {
      var top = windows[i].getBoundingClientRect().top + window.scrollY;
      if (top - 60 <= probe) { found = windows[i]; }
    }
    return found;
  }

  /* ---------------------------------------------------------------- *
   * 4. The mode line of the frame
   * ---------------------------------------------------------------- */

  function lineHeight() {
    var probe = $(".prose, .lead, .window__body p");
    if (probe) {
      var height = parseFloat(window.getComputedStyle(probe).lineHeight);
      if (height && !isNaN(height)) { return height; }
    }
    return 26;
  }

  function updateModeLine() {
    var scrolled = window.scrollY;
    var scrollable = doc.documentElement.scrollHeight - window.innerHeight;
    var percent = scrollable > 0 ? Math.round((scrolled / scrollable) * 100) : 0;
    var line = Math.round(scrolled / lineHeight()) + 1;

    if (positionEl) { positionEl.textContent = "U:" + clamp(percent, 0, 100) + "%-"; }
    if (lineEl) { lineEl.textContent = "L" + line; }

    var buffer = currentWindow();
    if (buffer) { setActiveBuffer(buffer); }
  }

  function tickClock() {
    var now = new Date();
    var hours = ("0" + now.getHours()).slice(-2);
    var minutes = ("0" + now.getMinutes()).slice(-2);
    if (clockEl) { clockEl.textContent = hours + ":" + minutes; }
  }

  /* ---------------------------------------------------------------- *
   * 5. The minibuffer — M-x
   * ---------------------------------------------------------------- */

  var COMMANDS = {
    "yeah": {
      describe: "Start the Yeah agent in this Emacs",
      run: function () { goTo("#scratch"); }
    },
    "yeah-doctor": {
      describe: "Inspect the local diagnostics",
      run: function () { goTo("#status"); }
    },
    "open-file": {
      describe: "Open a file: the installation buffer",
      run: function () { goTo("#install"); }
    },
    "find-file": {
      describe: "Find text in the buffer",
      run: function () { openSearch(); }
    },
    "switch-to-buffer": {
      describe: "Prompt for a buffer name, and select that buffer in the current window",
      run: function () { openBufferPrompt(); }
    },
    "recenter": {
      describe: "Recentre the buffer on its first line",
      run: function () { window.scrollTo({ top: 0, behavior: "smooth" }); }
    },
    "toggle-theme": {
      describe: "Change between the Emacs themes",
      run: function () { toggleTheme(); }
    },
    "split-window-below": {
      describe: "Split the frame: the two windows side by side",
      run: function () { goTo("#split"); }
    },
    "toggle-frames": {
      describe: "Hide or show the chrome of the frame",
      run: function () { toggleChrome(); }
    },
    "quit": {
      describe: "Close the minibuffer",
      run: function () {}
    }
  };

  var COMMAND_NAMES = Object.keys(COMMANDS).sort();

  var miniState = "closed";   /* closed | command | search | buffer */
  var prefix = null;

  function setMiniState(state) {
    miniState = state;
    if (!echoArea || !minibuffer) { return; }
    var active = state !== "closed";
    echoArea.classList.toggle("is-active", active);
    if (state === "search") {
      setSearchPrompt(0, "");
      minibuffer.placeholder = "search in buffer…";
    } else if (state === "buffer") {
      minibufferPrompt.textContent = "Switch to buffer: ";
      minibuffer.placeholder = "buffer name";
    } else if (state === "command") {
      /* The prompt of the extended command ends in a space, as it does in
         Emacs 30.2 (`lisp/simple.el'). */
      minibufferPrompt.textContent = "M-x ";
      minibuffer.placeholder = "";
    } else {
      minibufferPrompt.textContent = "";
      minibuffer.placeholder = "M-x yeah";
    }
  }

  /* The prompt of the incremental search is the one of Emacs: `I-search: ',
     with the number of the match and the number of the matches in front of
     it, the way `isearch-lazy-count' formats them, and `failing ' in front
     of it when the search finds nothing. */
  function setSearchPrompt(count, query) {
    if (!query) {
      minibufferPrompt.textContent = "I-search: ";
      return;
    }
    minibufferPrompt.textContent = count ? "1/" + count + " I-search: " : "failing I-search: ";
  }

  function openMinibuffer() {
    setMiniState("command");
    minibuffer.value = "";
    minibuffer.focus();
  }

  /* `switch-to-buffer' asks for the name of a buffer in the minibuffer. */
  function openBufferPrompt() {
    setMiniState("buffer");
    minibuffer.value = "";
    minibuffer.focus();
  }

  function closeMinibuffer() {
    if (miniState === "search") { clearSearch(); }
    setMiniState("closed");
    minibuffer.value = "";
    minibuffer.blur();
  }

  function runCommand(text) {
    var name = (text || "").trim();
    if (!name) { closeMinibuffer(); return; }

    var command = COMMANDS[name];
    if (!command) {
      /* Emacs 30.2 refuses a name that is not a command with exactly this
         message (lisp/simple.el: `(unless (commandp function) (error
         "`%s' is not a valid command name" command-name))').  The message
         about a void function belongs to the Elisp reader, not to `M-x'. */
      say("‘" + name + "’ is not a valid command name", "error");
      return;
    }
    say(command.describe, "success");
    closeMinibuffer();
    command.run();
  }

  function completeCommand() {
    var value = minibuffer.value;
    if (!value) { return; }
    var matches = COMMAND_NAMES.filter(function (name) {
      return name.indexOf(value) === 0;
    });
    if (matches.length === 1) {
      minibuffer.value = matches[0];
    } else if (matches.length > 1) {
      say(matches.join("  "));
    }
  }

  /* The completion of `switch-to-buffer' is over the names of the buffers
     of the frame. */
  function completeBuffer() {
    var value = minibuffer.value;
    var matches = bufferNames().filter(function (name) {
      return name.indexOf(value) === 0;
    });
    if (matches.length === 1) {
      minibuffer.value = matches[0];
    } else if (matches.length > 1) {
      say(matches.join("  "));
    }
  }

  /* Next Buffer and Previous Buffer walk the buffers of the frame in a
     cyclic order. */
  function stepBuffer(delta) {
    if (!windows.length) { return; }
    var current = currentWindow();
    var index = current ? windows.indexOf(current) : -1;
    var target = windows[(index + delta + windows.length) % windows.length];
    if (!target) { return; }
    setActiveBuffer(target);
    goTo("#" + target.id);
  }

  /* ---------------------------------------------------------------- *
   * 6. Incremental search — C-s
   * ---------------------------------------------------------------- */

  var searchMarks = [];
  var searchCurrent = null;

  function clearSearch() {
    searchMarks.forEach(function (mark) {
      var parent = mark.parentNode;
      if (!parent) { return; }
      while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
      parent.removeChild(mark);
      parent.normalize();
    });
    searchMarks = [];
    searchCurrent = null;
  }

  function highlightSearch(query) {
    clearSearch();
    if (!query || !content) { return 0; }

    var walker = doc.createTreeWalker(content, NodeFilter.SHOW_TEXT, null);
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) {
      if (!node.nodeValue || !node.nodeValue.trim()) { continue; }
      if (node.parentElement && node.parentElement.closest("button, .mode-line__right")) { continue; }
      nodes.push(node);
    }

    var lower = query.toLowerCase();
    var count = 0;

    nodes.forEach(function (textNode) {
      var text = textNode.nodeValue;
      var haystack = text.toLowerCase();
      var at = haystack.indexOf(lower);
      if (at === -1) { return; }

      var fragment = doc.createDocumentFragment();
      var consumed = 0;
      while (at !== -1) {
        if (at > consumed) {
          fragment.appendChild(doc.createTextNode(text.slice(consumed, at)));
        }
        var mark = doc.createElement("mark");
        mark.className = "isearch";
        mark.appendChild(doc.createTextNode(text.slice(at, at + query.length)));
        fragment.appendChild(mark);
        searchMarks.push(mark);
        count += 1;
        consumed = at + query.length;
        at = haystack.indexOf(lower, consumed);
      }
      if (consumed < text.length) {
        fragment.appendChild(doc.createTextNode(text.slice(consumed)));
      }
      textNode.parentNode.replaceChild(fragment, textNode);
    });

    if (searchMarks.length) {
      searchCurrent = searchMarks[0];
      searchCurrent.classList.add("isearch-current");
      if (searchCurrent.scrollIntoView) {
        searchCurrent.scrollIntoView({ block: "center", behavior: "smooth" });
      }
    }
    return count;
  }

  function openSearch() {
    setMiniState("search");
    minibuffer.value = "";
    minibuffer.focus();
  }

  /* ---------------------------------------------------------------- *
   * 7. Chrome, zoom, copy
   * ---------------------------------------------------------------- */

  function toggleChrome() {
    var off = body.classList.toggle("chrome-off");
    say(off ? "Frame chrome hidden" : "Frame chrome shown");
  }

  var scale = 1;

  function setScale(next) {
    scale = clamp(Math.round(next * 20) / 20, 0.8, 1.4);
    root.style.setProperty("--ui-scale", String(scale));
    say("Zoom " + Math.round(scale * 100) + "%");
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var area = doc.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.left = "-9999px";
    doc.body.appendChild(area);
    area.select();
    var copied = false;
    try { copied = doc.execCommand("copy"); } catch (error) { copied = false; }
    doc.body.removeChild(area);
    return copied ? Promise.resolve() : Promise.reject(new Error("copy refused"));
  }

  $$("[data-copy-target]").forEach(function (button) {
    button.hidden = false;
    button.addEventListener("click", function () {
      var target = doc.getElementById(button.dataset.copyTarget);
      if (!target) { return; }
      var text = target.textContent.trim();
      copyText(text).then(function () {
        button.textContent = "copied";
        button.classList.add("is-done");
        say("Copied " + text.length + " characters", "success");
        window.setTimeout(function () {
          button.textContent = "copy";
          button.classList.remove("is-done");
        }, 1600);
      }, function () {
        button.textContent = "failed";
        button.classList.add("is-error");
        say("Could not write to the clipboard", "error");
        window.setTimeout(function () {
          button.textContent = "copy";
          button.classList.remove("is-error");
        }, 1600);
      });
    });
  });

  /* ---------------------------------------------------------------- *
   * 8. The commands of the menu bar
   * ---------------------------------------------------------------- */

  var ACTIONS = {
    "toggle-theme": toggleTheme,
    "theme-light": function () { setTheme("light"); say("Theme set to " + themeLabel("light")); },
    "theme-dark": function () { setTheme("dark"); say("Theme set to " + themeLabel("dark")); },
    "zoom-in": function () { setScale(scale + 0.05); },
    "zoom-out": function () { setScale(scale - 0.05); },
    "toggle-chrome": toggleChrome,
    "isearch": openSearch,
    "copy-install": function () {
      var snippet = doc.getElementById("install-vc");
      if (!snippet) { return; }
      copyText(snippet.textContent.trim()).then(function () {
        say("Install command copied", "success");
      }, function () {
        say("Could not write to the clipboard", "error");
      });
    },
    "copy-url": function () {
      copyText(window.location.href).then(function () {
        say("Page address copied", "success");
      }, function () {
        say("Could not write to the clipboard", "error");
      });
    },
    "select-all": function () {
      var selection = window.getSelection();
      if (content) {
        var range = doc.createRange();
        range.selectNodeContents(content);
        selection.removeAllRanges();
        selection.addRange(range);
      }
      say("Selected the whole buffer");
    },
    "new-buffer": function () { openBuffersMenu(); },
    "next-buffer": function () { stepBuffer(1); },
    "previous-buffer": function () { stepBuffer(-1); },
    "switch-to-buffer": function () { openBufferPrompt(); }
  };

  doc.addEventListener("click", function (event) {
    var trigger = event.target.closest("[data-action]");
    if (!trigger) { return; }
    var action = ACTIONS[trigger.dataset.action];
    if (action) {
      event.preventDefault();
      action();
    }
  });

  /* ---------------------------------------------------------------- *
   * 9. The keys Emacs binds
   * ---------------------------------------------------------------- */

  doc.addEventListener("keydown", function (event) {
    var inField = event.target && /^(INPUT|TEXTAREA)$/.test(event.target.tagName);

    if (event.key === "Escape") {
      if (miniState !== "closed") {
        event.preventDefault();
        closeMinibuffer();
      }
      return;
    }

    if (inField) { return; }

    if (event.altKey && (event.key === "x" || event.key === "X")) {
      event.preventDefault();
      openMinibuffer();
      return;
    }

    if (event.ctrlKey && !event.altKey && (event.key === "s" || event.key === "S")) {
      event.preventDefault();
      openSearch();
      return;
    }

    if (event.ctrlKey && !event.altKey && (event.key === "x" || event.key === "X")) {
      event.preventDefault();
      prefix = "C-x";
      say("C-x");
      return;
    }

    if (prefix === "C-x") {
      var key = (event.key || "").toLowerCase();
      prefix = null;
      if (key === "b") { event.preventDefault(); openBufferPrompt(); return; }
      if (key === "f") { event.preventDefault(); openSearch(); return; }
      if (key === "2") { event.preventDefault(); goTo("#split"); return; }
      if (key === "g") { event.preventDefault(); say(""); return; }
      say("");
      return;
    }

    if (event.ctrlKey && !event.altKey && (event.key === "g" || event.key === "G")) {
      event.preventDefault();
      if (miniState !== "closed") { closeMinibuffer(); }
      else { say(""); }
      return;
    }
  });

  minibuffer.addEventListener("keydown", function (event) {
    if (event.key === "Enter") {
      event.preventDefault();
      if (miniState === "search") {
        var count = searchMarks.length;
        say(count === 1 ? "1 match" : count + " matches", count ? "success" : "error");
        setMiniState("closed");
        minibuffer.blur();
      } else if (miniState === "buffer") {
        var name = minibuffer.value.trim();
        var target = bufferFor(name);
        if (!target) {
          say("No buffer matching " + name, "error");
          return;
        }
        closeMinibuffer();
        setActiveBuffer(target);
        goTo("#" + target.id);
        say("Buffer: " + target.dataset.buffer, "success");
      } else {
        runCommand(minibuffer.value);
      }
      return;
    }

    if (event.key === "Tab") {
      event.preventDefault();
      if (miniState === "search") { return; }
      if (miniState === "buffer") { completeBuffer(); return; }
      completeCommand();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      closeMinibuffer();
    }
  });

  minibuffer.addEventListener("input", function () {
    if (miniState === "search") {
      var query = minibuffer.value.trim();
      var count = highlightSearch(query);
      setSearchPrompt(count, query);
    }
  });

  minibuffer.addEventListener("blur", function () {
    if (miniState !== "closed") {
      if (miniState === "search") { clearSearch(); }
      setMiniState("closed");
    }
  });

  /* Clicking straight into the echo area is the way into the minibuffer:
     the prompt appears as soon as the input holds the focus. */
  minibuffer.addEventListener("focus", function () {
    if (miniState === "closed") { setMiniState("command"); }
  });

  echoArea.addEventListener("click", function (event) {
    if (event.target === echoArea && miniState === "closed") { openMinibuffer(); }
  });

  /* ---------------------------------------------------------------- *
   * 10. The frame keeps up with the reader
   * ---------------------------------------------------------------- */

  var scheduled = false;

  function onScroll() {
    if (scheduled) { return; }
    scheduled = true;
    window.requestAnimationFrame(function () {
      scheduled = false;
      updateModeLine();
    });
  }

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", function () {
    onScroll();
    tickClock();
  });

  tickClock();
  window.setInterval(tickClock, 15000);
  updateModeLine();

  /* The frame starts idle: the echo area waits, and the prompt is empty
     until a command is asked for. */
  setMiniState("closed");
  say("Type M-x for the minibuffer, C-s to search");
})();
