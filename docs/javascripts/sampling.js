// Sampling explainers for "How it works".
//
// 1. Simulator (#ta-sim): one 64 x 64 module running the readout firmware's sampling loop
//    (acquisition/firmware/.../binary_sampling_64x64_6MHz_BigBuffer_Vis_ID.ino, binarySampling()):
//      - taxels that triggered neighbour sampling last frame are read first (up to 50 "priority centres");
//      - then the fixed coarse-to-fine background order (ctrMsrRows/ctrMsrCols, loaded from scan_order.json),
//        shifted by one column every frame and by one row after each full sweep of columns;
//      - any reading above threshold reads its unread 3 x 3 neighbours, recursively;
//      - everything stops after M readings, and each taxel is read at most once per frame.
//    The "true" pressure is a simulated paw that follows the pointer (or walks by itself when idle).
// 2. Replay (#ta-replay): a real recording, packet by packet (replay.bin, written by
//    site_tools/export_sampling.py): for every frame of every board, which taxels it read and their values.
(function () {
  "use strict";
  var N = 64, NN = N * N;

  // inferno-like ramp for pressure, from deep purple to pale yellow
  var STOPS = [[87, 16, 110], [188, 55, 84], [249, 142, 9], [252, 255, 164]];
  function ramp(x) {
    x = Math.max(0, Math.min(1, x)) * (STOPS.length - 1);
    var i = Math.min(Math.floor(x), STOPS.length - 2), f = x - i, a = STOPS[i], b = STOPS[i + 1];
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
  }
  var UNREAD = [11, 8, 15], READ = [70, 74, 94];

  function paintTaxel(img, W, x, y, s, rgb) {
    var g = s >= 6 ? 1 : 0;
    for (var j = 0; j < s - g; j++) {
      var o = ((y * s + j) * W + x * s) * 4;
      for (var i = 0; i < s - g; i++, o += 4) { img[o] = rgb[0]; img[o + 1] = rgb[1]; img[o + 2] = rgb[2]; img[o + 3] = 255; }
    }
  }

  function colourFor(v, thr, read, showRead) {
    if (!read) return UNREAD;
    if (v > thr) return ramp(0.15 + 0.85 * Math.pow(Math.min(1, (v - thr) / (3600 - thr)), 0.75));
    return showRead ? READ : UNREAD;
  }

  // ---------------------------------------------------------------- firmware sampling loop
  function Sampler(order) {
    this.R = order.rows; this.C = order.cols;
    this.offX = 0; this.offY = 0; this.centres = [];
    this.read = new Uint8Array(NN); this.val = new Float32Array(NN); this.n = 0;
  }
  Sampler.prototype.frame = function (truth, M, thr) {
    var self = this, read = this.read, val = this.val, idx = 0, next = [];
    read.fill(0); val.fill(0);
    function addCentre(r, c) {
      for (var i = 0; i < next.length; i++) if (next[i][0] === r && next[i][1] === c) return;
      if (next.length < 50) next.push([r, c]);
    }
    function take(r, c) { var p = r * N + c, v = truth[p]; read[p] = 1; val[p] = v; idx++; return v; }
    var colOrd = [0, -1, 1];
    function neighbours(cr, cc, orig) {
      if (orig) addCentre(cr, cc);
      for (var jj = 0; jj < 3; jj++) {
        var c = cc + colOrd[jj];
        if (c < 0 || c >= N) continue;
        for (var r = cr - 1; r <= cr + 1; r++) {
          if (r < 0 || r >= N) continue;
          if (idx >= M) return;
          if (read[r * N + c]) continue;
          var v = take(r, c);
          if (idx >= M) return;
          if (v > thr) { neighbours(r, c, false); if (idx >= M) return; }
        }
      }
    }
    function visit(r, c) {   // returns false when the budget is spent
      if (read[r * N + c]) return true;
      var v = take(r, c);
      if (idx >= M) return false;
      if (v > thr) { neighbours(r, c, true); if (idx >= M) return false; }
      return true;
    }
    for (var p = 0; p < this.centres.length && idx < M; p++) if (!visit(this.centres[p][0], this.centres[p][1])) break;
    for (var i = 0; i < NN && idx < M; i++) {
      if (!visit((this.R[i] + this.offX) % N, (this.C[i] + this.offY) % N)) break;
    }
    this.offY++; if (this.offY >= N) { this.offY = 0; this.offX = (this.offX + 1) % N; }
    this.centres = next; this.n = idx;
    return idx;
  };

  // ---------------------------------------------------------------- simulated paws
  // A rat-like hind-paw print: a palm and four toes, about 9 x 7 taxels, pointing along `ang`.
  var PADS = [[0, 0, 2.0, 1.0], [3.3, -2.6, 0.95, 0.75], [4.4, -0.9, 0.95, 0.85], [4.4, 0.9, 0.95, 0.85], [3.3, 2.6, 0.95, 0.75], [-2.4, 0, 1.6, 0.55]];
  function stamp(truth, x, y, ang, amp) {
    var ca = Math.cos(ang), sa = Math.sin(ang);
    for (var k = 0; k < PADS.length; k++) {
      var px = x + PADS[k][0] * ca - PADS[k][1] * sa, py = y + PADS[k][0] * sa + PADS[k][1] * ca, s = PADS[k][2], a = PADS[k][3] * amp;
      var r0 = Math.max(0, Math.floor(py - 3 * s)), r1 = Math.min(N - 1, Math.ceil(py + 3 * s));
      var c0 = Math.max(0, Math.floor(px - 3 * s)), c1 = Math.min(N - 1, Math.ceil(px + 3 * s));
      for (var r = r0; r <= r1; r++) for (var c = c0; c <= c1; c++) {
        var d2 = ((c - px) * (c - px) + (r - py) * (r - py)) / (2 * s * s);
        truth[r * N + c] += a * Math.exp(-d2);
      }
    }
  }

  function setupSim(root, order) {
    var cTrue = root.querySelector("canvas[data-view=true]"), cRead = root.querySelector("canvas[data-view=read]");
    var S = 8, W = N * S;
    [cTrue, cRead].forEach(function (c) { c.width = W; c.height = W; });
    var gT = cTrue.getContext("2d"), gR = cRead.getContext("2d");
    var iT = gT.createImageData(W, W), iR = gR.createImageData(W, W);
    var mIn = root.querySelector("input[name=M]"), tIn = root.querySelector("input[name=thr]");
    var mOut = root.querySelector("output[name=M]"), tOut = root.querySelector("output[name=thr]");
    var stats = root.querySelector(".ta-widget__stats"), playBtn = root.querySelector("button[data-act=play]");
    var sampler = new Sampler(order), truth = new Float32Array(NN);
    var pointer = null, held = 0, auto = 0, playing = true, last = 0;

    function pos(e) {
      var b = cRead.getBoundingClientRect(), t = e.target === cTrue ? cTrue.getBoundingClientRect() : b;
      return [(e.clientX - t.left) / t.width * N, (e.clientY - t.top) / t.height * N];
    }
    function down(e) { pointer = pos(e); e.preventDefault(); }
    function move(e) { if (pointer) pointer = pos(e); }
    function up() { pointer = null; }
    [cTrue, cRead].forEach(function (c) {
      c.addEventListener("pointerdown", function (e) { c.setPointerCapture(e.pointerId); down(e); });
      c.addEventListener("pointermove", move);
      c.addEventListener("pointerup", up); c.addEventListener("pointercancel", up);
    });
    mIn.addEventListener("input", function () { mOut.value = mIn.value; });
    tIn.addEventListener("input", function () { tOut.value = tIn.value; });
    playBtn.addEventListener("click", function () {
      playing = !playing; playBtn.setAttribute("aria-pressed", String(!playing)); playBtn.textContent = playing ? "Pause" : "Play";
      if (playing) requestAnimationFrame(tick);
    });

    function build(t) {
      truth.fill(0);
      for (var i = 0; i < NN; i++) truth[i] = 40 + 90 * Math.random();   // unloaded floor: small readings
      if (pointer) { held = Math.min(1, held + 0.12); stamp(truth, pointer[0], pointer[1], -Math.PI / 2, 3400 * held); auto = 0; }
      else {
        held = Math.max(0, held - 0.2);
        auto += 1;
        if (auto > 45) {   // nobody is pressing: two paws walk across the module
          var ph = (t / 1600) % 2, x = 6 + 52 * (ph % 1);
          var a1 = Math.max(0, Math.sin(Math.PI * ((ph * 3) % 1))), a2 = Math.max(0, Math.sin(Math.PI * ((ph * 3 + 0.5) % 1)));
          stamp(truth, x, 22, 0, 3300 * a1);
          stamp(truth, Math.min(58, x + 9), 40, 0, 3300 * a2);
        }
      }
    }

    function draw() {
      var M = +mIn.value, thr = +tIn.value, read = sampler.read, val = sampler.val, hot = 0, hotRead = 0;
      for (var r = 0; r < N; r++) for (var c = 0; c < N; c++) {
        var p = r * N + c, v = truth[p];
        if (v > thr) { hot++; if (read[p]) hotRead++; }
        paintTaxel(iT.data, W, c, r, S, v > thr ? ramp(0.15 + 0.85 * Math.pow(Math.min(1, (v - thr) / (3600 - thr)), 0.75)) : UNREAD);
        paintTaxel(iR.data, W, c, r, S, colourFor(val[p], thr, read[p], true));
      }
      gT.putImageData(iT, 0, 0); gR.putImageData(iR, 0, 0);
      stats.textContent = "Measured in this frame: " + sampler.n + " of 4,096 taxels (" + (100 * sampler.n / NN).toFixed(1) + "%)" +
        (hot ? "  ·  above-threshold taxels measured: " + hotRead + " of " + hot + " (" + Math.round(100 * hotRead / hot) + "%)" : "  ·  no applied load");
    }

    function tick(t) {
      if (!playing) return;
      if (t - last > 33) {   // about 30 simulated frames per second on screen; the real board runs ~1,000
        last = t; build(t); sampler.frame(truth, +mIn.value, +tIn.value); draw();
      }
      requestAnimationFrame(tick);
    }
    var vis = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting && playing) requestAnimationFrame(tick); }); });
    vis.observe(root);
    build(0); sampler.frame(truth, +mIn.value, +tIn.value); draw();
  }

  // ---------------------------------------------------------------- real-data replay
  function setupReplay(root, meta, buf) {
    var cv = root.querySelector("canvas"), S = 6, W = 256 * S, H = 64 * S;
    cv.width = W; cv.height = H;
    var g = cv.getContext("2d"), img = g.createImageData(W, H);
    var boards = meta.boards.map(function (b) {
      var ts = new Float32Array(buf, b.ts, b.n), cnt = new Uint16Array(buf, b.count, b.n);
      var off = new Uint32Array(b.n + 1); for (var i = 0; i < b.n; i++) off[i + 1] = off[i] + cnt[i];
      return { ts: ts, off: off, idx: new Uint16Array(buf, b.idx, b.taxels), val: new Uint8Array(buf, b.val, b.taxels) };
    });
    var thr = meta.threshold / meta.value_scale;
    var speedSel = root.querySelector("select[name=speed]"), showRead = root.querySelector("input[name=showread]");
    var stats = root.querySelector(".ta-widget__stats"), playBtn = root.querySelector("button[data-act=play]");
    var stepBtn = root.querySelector("button[data-act=step]");
    var t = 0, span = meta.t1 - meta.t0, playing = false, lastT = null;
    var read = new Uint8Array(NN), vals = new Uint8Array(NN);

    function latest(b, tt) { var lo = 0, hi = b.ts.length - 1; if (b.ts[0] > tt) return -1; while (lo < hi) { var m = (lo + hi + 1) >> 1; if (b.ts[m] <= tt) lo = m; else hi = m - 1; } return lo; }
    function draw() {
      var total = 0, sr = showRead.checked;
      for (var k = 0; k < 4; k++) {
        var b = boards[k], p = latest(b, t);
        read.fill(0); vals.fill(0);
        if (p >= 0) for (var i = b.off[p]; i < b.off[p + 1]; i++) { read[b.idx[i]] = 1; vals[b.idx[i]] = b.val[i]; }
        total += p >= 0 ? b.off[p + 1] - b.off[p] : 0;
        for (var r = 0; r < N; r++) for (var c = 0; c < N; c++) {
          var q = r * N + c, v = vals[q], rgb;
          if (v > thr) rgb = ramp(0.15 + 0.85 * Math.pow(Math.min(1, (v - thr) / (225 - thr)), 0.75));
          else rgb = sr ? (read[q] ? READ : UNREAD) : [14, 11, 19];
          paintTaxel(img.data, W, k * N + c, r, S, rgb);
        }
      }
      g.putImageData(img, 0, 0);
      stats.textContent = "t = " + (meta.t0 + t).toFixed(4) + " s  ·  measured in the current frames: " + total.toLocaleString() + " of 16,384 taxels (" + (100 * total / 16384).toFixed(1) + "%)";
    }
    function nextPacketTime() {   // the earliest packet after t on any board
      var best = Infinity; boards.forEach(function (b) { var p = latest(b, t); if (p + 1 < b.ts.length) best = Math.min(best, b.ts[p + 1]); });
      return best;
    }
    function tick(now) {
      if (!playing) { lastT = null; return; }
      if (lastT !== null) { t += (now - lastT) / 1000 * (+speedSel.value); if (t > span) t = 0; }
      lastT = now; draw(); requestAnimationFrame(tick);
    }
    playBtn.addEventListener("click", function () {
      playing = !playing; playBtn.textContent = playing ? "Pause" : "Play"; playBtn.setAttribute("aria-pressed", String(playing));
      if (playing) requestAnimationFrame(tick);
    });
    stepBtn.addEventListener("click", function () { playing = false; playBtn.textContent = "Play"; var n = nextPacketTime(); t = n === Infinity ? 0 : n; draw(); });
    showRead.addEventListener("change", draw);
    t = 0.13; draw();
  }

  function init() {
    var sim = document.getElementById("ta-sim"), rep = document.getElementById("ta-replay");
    if (!sim && !rep) return;
    var base = (sim || rep).getAttribute("data-src");
    if (sim) fetch(base + "scan_order.json").then(function (r) { return r.json(); }).then(function (o) { setupSim(sim, o); });
    if (rep) Promise.all([fetch(base + "replay.json").then(function (r) { return r.json(); }),
                          fetch(base + "replay.bin").then(function (r) { return r.arrayBuffer(); })])
      .then(function (a) { setupReplay(rep, a[0], a[1]); });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();
})();
