/* Yeah — progressive enhancement for a readable static page. */

(function () {
  "use strict";

  function reset(button, original) {
    window.setTimeout(function () {
      button.textContent = original;
      button.classList.remove("is-done", "is-error");
    }, 1600);
  }

  function fallback(text) {
    var area = document.createElement("textarea");
    var copied = false;
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    try { copied = document.execCommand("copy"); } catch (error) { copied = false; }
    document.body.removeChild(area);
    return copied;
  }

  document.querySelectorAll("[data-copy-target]").forEach(function (button) {
    button.hidden = false;
    button.setAttribute("aria-live", "polite");

    button.addEventListener("click", function () {
      var target = document.getElementById(button.dataset.copyTarget);
      if (!target) { return; }

      var text = target.textContent.trim();
      var original = "[ copy ]";
      var finish = function (copied) {
        button.textContent = copied ? "[ copied ]" : "[ copy failed ]";
        button.classList.toggle("is-done", copied);
        button.classList.toggle("is-error", !copied);
        reset(button, original);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { finish(true); }).catch(function () {
          finish(fallback(text));
        });
      } else {
        finish(fallback(text));
      }
    });
  });

  var sections = Array.prototype.slice.call(document.querySelectorAll("main section[id]"));
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a"));

  if (!("IntersectionObserver" in window) || !sections.length || !links.length) { return; }

  var spy = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) { return; }
      links.forEach(function (link) {
        if (link.getAttribute("href") === "#" + entry.target.id) {
          link.setAttribute("aria-current", "location");
        } else {
          link.removeAttribute("aria-current");
        }
      });
    });
  }, { rootMargin: "-25% 0px -65% 0px", threshold: 0 });

  sections.forEach(function (section) { spy.observe(section); });
})();
