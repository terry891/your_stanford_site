(function () {
  "use strict";

  var root = document.documentElement;
  var reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  var clamp = function (n) { return n < 0 ? 0 : n > 1 ? 1 : n; };

  /* Theme ---------------------------------------------------------------- */
  var themeBtn = document.querySelector("[data-theme-toggle]");
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var next = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try { localStorage.setItem("theme", next); } catch (e) {}
    });
  }

  /* Mobile navigation ----------------------------------------------------- */
  var navBtn = document.querySelector("[data-nav-toggle]");
  var nav = document.getElementById("primary-nav");
  if (navBtn && nav) {
    var setNav = function (open) {
      nav.classList.toggle("is-open", open);
      navBtn.setAttribute("aria-expanded", String(open));
    };
    navBtn.addEventListener("click", function () { setNav(!nav.classList.contains("is-open")); });
    nav.addEventListener("click", function (e) { if (e.target.tagName === "A") setNav(false); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") setNav(false); });
  }

  /* Elements driven by scroll position ------------------------------------ */
  var header = document.querySelector(".site-header");
  var toTop = document.querySelector("[data-to-top]");
  var progress = document.querySelector(".progress");
  var parallax = document.querySelectorAll("[data-parallax]");
  var pin = document.querySelector("[data-pin]");
  var pinPanels = pin ? pin.querySelectorAll(".pin-panel") : [];
  var pinDots = pin ? pin.querySelectorAll(".pin-index i") : [];
  var rail = document.querySelector("[data-rail]");
  var railTrack = rail ? rail.querySelector(".rail-track") : null;

  if (pin && pinPanels.length && !reduced) {
    pin.style.height = 100 + pinPanels.length * 85 + "vh";
  }

  var measureRail = function () {
    if (!rail || !railTrack || reduced) return;
    var travel = Math.max(0, railTrack.scrollWidth - window.innerWidth + 32);
    railTrack.style.setProperty("--travel", travel + "px");
    rail.style.height = 100 + travel / window.innerHeight * 100 + "vh";
  };

  var track = function (el) {
    var box = el.getBoundingClientRect();
    return clamp((window.innerHeight - box.top) / (window.innerHeight + box.height));
  };

  var frame = function () {
    var y = window.scrollY;

    if (header) header.classList.toggle("is-stuck", y > 8);
    if (toTop) toTop.classList.toggle("is-visible", y > 700);

    if (progress) {
      var doc = document.documentElement.scrollHeight - window.innerHeight;
      progress.style.setProperty("--p", doc > 0 ? clamp(y / doc) : 0);
    }

    parallax.forEach(function (el) { el.style.setProperty("--p", track(el)); });

    if (pin && pinPanels.length && !reduced) {
      var pb = pin.getBoundingClientRect();
      var span = pin.offsetHeight - window.innerHeight;
      var p = span > 0 ? clamp(-pb.top / span) : 0;
      var step = Math.min(pinPanels.length - 1, Math.floor(p * pinPanels.length));
      pinPanels.forEach(function (panel, i) { panel.classList.toggle("is-on", i === step); });
      pinDots.forEach(function (dot, i) { dot.classList.toggle("is-on", i === step); });
    }

    if (rail && railTrack && !reduced) {
      var rb = rail.getBoundingClientRect();
      var rspan = rail.offsetHeight - window.innerHeight;
      railTrack.style.setProperty("--p", rspan > 0 ? clamp(-rb.top / rspan) : 0);
    }
  };

  var ticking = false;
  var onScroll = function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () { frame(); ticking = false; });
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", function () { measureRail(); frame(); });
  window.addEventListener("load", function () { measureRail(); frame(); });
  measureRail();
  frame();

  if (toTop) {
    toTop.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: reduced ? "auto" : "smooth" });
    });
  }

  /* Reveal fallback for browsers without scroll-driven animations --------- */
  var nativeTimeline = CSS.supports && CSS.supports("animation-timeline: view()");
  var revealables = document.querySelectorAll(".reveal");
  if (reduced || nativeTimeline) {
    if (reduced) revealables.forEach(function (el) { el.classList.add("is-in"); });
  } else if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.style.transitionDelay = (entry.target.dataset.delay || 0) + "ms";
        entry.target.classList.add("is-in");
        io.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    revealables.forEach(function (el) { io.observe(el); });
  } else {
    revealables.forEach(function (el) { el.classList.add("is-in"); });
  }

  /* Counters --------------------------------------------------------------- */
  var counters = document.querySelectorAll("[data-count]");
  if (counters.length && "IntersectionObserver" in window) {
    var co = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        co.unobserve(el);
        var target = parseFloat(el.dataset.count);
        var suffix = el.dataset.suffix || "";
        if (reduced) { el.textContent = target + suffix; return; }
        var start = performance.now();
        var tick = function (now) {
          var t = clamp((now - start) / 1100);
          var eased = 1 - Math.pow(1 - t, 3);
          el.textContent = Math.round(target * eased) + suffix;
          if (t < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
    }, { threshold: 0.5 });
    counters.forEach(function (el) { co.observe(el); });
  }

  /* Active section in the nav ---------------------------------------------- */
  var sections = document.querySelectorAll("section[id]");
  var navLinks = document.querySelectorAll('#primary-nav a[href*="#"]');
  if (sections.length && navLinks.length && "IntersectionObserver" in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navLinks.forEach(function (link) {
          var href = link.getAttribute("href");
          link.classList.toggle("is-active", href.slice(href.indexOf("#")) === "#" + entry.target.id);
        });
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    sections.forEach(function (s) { spy.observe(s); });
  }

  /* Project filtering -------------------------------------------------------- */
  var filters = document.querySelectorAll("[data-filter]");
  var items = document.querySelectorAll("[data-tags]");
  if (filters.length && items.length) {
    filters.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var want = btn.dataset.filter.toLowerCase();
        filters.forEach(function (b) { b.setAttribute("aria-pressed", String(b === btn)); });
        items.forEach(function (item) {
          var tags = item.dataset.tags.toLowerCase().split(/\s*,\s*/);
          item.hidden = want !== "all" && tags.indexOf(want) === -1;
        });
        measureRail();
      });
    });
  }

  /* Copy to clipboard --------------------------------------------------------- */
  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var done = function () {
        btn.classList.add("is-copied");
        setTimeout(function () { btn.classList.remove("is-copied"); }, 1600);
      };
      if (navigator.clipboard) {
        navigator.clipboard.writeText(btn.dataset.copy).then(done, function () {});
        return;
      }
      var t = document.createElement("textarea");
      t.value = btn.dataset.copy;
      document.body.appendChild(t);
      t.select();
      try { document.execCommand("copy"); done(); } catch (e) {}
      document.body.removeChild(t);
    });
  });

  /* Print button ------------------------------------------------------------- */
  document.querySelectorAll("[data-print]").forEach(function (btn) {
    btn.addEventListener("click", function () { window.print(); });
  });

  /* Footer year ----------------------------------------------------------------- */
  var year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());
})();
