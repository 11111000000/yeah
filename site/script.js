/* Yeah — static site behaviour.
   Progressive enhancement only: the page is readable with JavaScript off. */

(function () {
  "use strict";

  /* ── copy to clipboard ─────────────────────────────────────────── */

  document.querySelectorAll("[data-copy-target]").forEach(function (button) {
    button.addEventListener("click", function () {
      var target = document.getElementById(button.dataset.copyTarget);
      if (!target) { return; }

      var text = target.textContent.trim();
      var done = function () {
        var original = button.textContent;
        button.textContent = "Copied";
        button.classList.add("is-done");
        window.setTimeout(function () {
          button.textContent = original;
          button.classList.remove("is-done");
        }, 1600);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(function () { fallback(text, done); });
      } else {
        fallback(text, done);
      }
    });
  });

  function fallback(text, done) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "absolute";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    try { document.execCommand("copy"); done(); } catch (error) { /* clipboard unavailable */ }
    document.body.removeChild(area);
  }

  /* ── reveal on scroll ──────────────────────────────────────────── */

  var revealables = document.querySelectorAll(".reveal");

  if (!("IntersectionObserver" in window)) {
    revealables.forEach(function (el) { el.classList.add("is-visible"); });
  } else {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) { return; }
        var el = entry.target;
        var siblings = Array.prototype.slice.call(el.parentElement.children);
        var index = siblings.indexOf(el);
        var delay = Math.min(Math.max(index, 0), 6) * 60;
        window.setTimeout(function () { el.classList.add("is-visible"); }, delay);
        observer.unobserve(el);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });

    revealables.forEach(function (el) { observer.observe(el); });
  }

  /* ── mark the current section in the navigation ────────────────── */

  var sections = Array.prototype.slice.call(
    document.querySelectorAll("main section[id]")
  );
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a"));

  if ("IntersectionObserver" in window && sections.length && links.length) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) { return; }
        links.forEach(function (link) {
          var active = link.getAttribute("href") === "#" + entry.target.id;
          link.style.color = active ? "var(--fg)" : "";
          link.style.borderBottomColor = active ? "var(--accent-soft)" : "";
        });
      });
    }, { rootMargin: "-40% 0px -55% 0px" });

    sections.forEach(function (section) { spy.observe(section); });
  }
})();
