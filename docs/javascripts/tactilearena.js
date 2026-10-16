// Clips.
//
// Loops: <video data-loop muted loop playsinline preload="none" ...> play while at least a quarter of them is
// on screen and pause otherwise, so a page full of clips only decodes what is visible and loads nothing until
// it scrolls into view. With "reduce motion" set they stay paused, with controls.
//
// Posters: a clip below the first screen names its still as data-poster="..." rather than poster="...",
// because browsers fetch every poster at page load. The still is set once the clip comes within about a
// screen and a half of the viewport.
(function () {
  "use strict";

  function setPoster(v) {
    var src = v.getAttribute("data-poster");
    if (src) { v.setAttribute("poster", src); v.removeAttribute("data-poster"); }
  }

  function posters() {
    var lazy = document.querySelectorAll("video[data-poster]");
    if (!lazy.length) return;
    if (!("IntersectionObserver" in window)) { lazy.forEach(setPoster); return; }
    var near = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { setPoster(e.target); near.unobserve(e.target); } });
    }, { rootMargin: "150% 0px 150% 0px" });
    lazy.forEach(function (v) { near.observe(v); });
  }

  function loops() {
    var videos = document.querySelectorAll("video[data-loop]");
    if (!videos.length) return;
    var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("IntersectionObserver" in window)) {
      videos.forEach(function (v) { v.removeAttribute("autoplay"); v.pause(); v.controls = true; });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        var v = e.target;
        if (e.isIntersecting) {
          setPoster(v);
          if (v.preload === "none") v.preload = "auto";
          var p = v.play();
          if (p && p.catch) p.catch(function (err) { if (!err || err.name !== "AbortError") v.controls = true; });
        } else {
          v.pause();
        }
      });
    }, { threshold: 0.25 });
    videos.forEach(function (v) { v.muted = true; observer.observe(v); });
  }

  function setup() { posters(); loops(); }
  if (document.readyState === "complete") setup();
  else window.addEventListener("load", setup, { once: true });
})();
