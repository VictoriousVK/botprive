/* Minimal SVG charts (no dependencies, CSP-safe). Specs: 2px lines, 10% area wash, hairline
   grid, end dot r=4 with a 2px surface ring, bars <= 18px with a 4px rounded data end and a
   square baseline end, crosshair + tooltip listing every series, keyboard navigation.
   All text is inserted with textContent. Colours come from CSS classes (role tokens). */
(function () {
  "use strict";
  var NS = "http://www.w3.org/2000/svg";

  function svgEl(tag, attrs, parent) {
    var e = document.createElementNS(NS, tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (parent) parent.appendChild(e);
    return e;
  }
  function htmlEl(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function niceStep(range, count) {
    var raw = range / Math.max(1, count);
    var mag = Math.pow(10, Math.floor(Math.log10(raw || 1)));
    var norm = raw / mag;
    var step = norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10;
    return step * mag;
  }
  function niceTicks(min, max, count) {
    if (min === max) { min -= 1; max += 1; }
    var step = niceStep(max - min, count);
    var start = Math.floor(min / step) * step, end = Math.ceil(max / step) * step, out = [];
    for (var v = start; v <= end + step / 2; v += step) out.push(Math.round(v / step) * step);
    return out;
  }

  function observe(container, render) {
    render();
    if (container._ro) container._ro.disconnect();
    if (window.ResizeObserver) {
      var last = container.clientWidth;
      container._ro = new ResizeObserver(function () {
        if (Math.abs(container.clientWidth - last) > 4) { last = container.clientWidth; render(); }
      });
      container._ro.observe(container);
    }
  }

  function emptyState(container, height, text) {
    var svg = svgEl("svg", { viewBox: "0 0 400 " + height, height: height, role: "img", "aria-label": text });
    var t = svgEl("text", { x: 200, y: height / 2, "text-anchor": "middle", "class": "empty-msg" }, svg);
    t.textContent = text;
    container.appendChild(svg);
  }

  /* ---------------- line / area ---------------- */
  function line(container, opts) {
    observe(container, function () {
      container.textContent = "";
      var height = opts.height || 240;
      var series = (opts.series || []).filter(function (s) { return s.points && s.points.length; });
      if (!series.length || series[0].points.length < 2) { emptyState(container, height, opts.emptyText || "Pas encore de données"); return; }
      var width = Math.max(280, container.clientWidth || 600);
      var m = { l: 70, r: 78, t: 12, b: 26 };
      var tMin = Infinity, tMax = -Infinity, vMin = Infinity, vMax = -Infinity;
      series.forEach(function (s) { s.points.forEach(function (p) {
        tMin = Math.min(tMin, p.t); tMax = Math.max(tMax, p.t); vMin = Math.min(vMin, p.v); vMax = Math.max(vMax, p.v);
      }); });
      if (opts.zeroBaseline) { vMin = Math.min(vMin, 0); vMax = Math.max(vMax, 0); }
      var ticks = niceTicks(vMin, vMax, 4);
      vMin = ticks[0]; vMax = ticks[ticks.length - 1];
      var X = function (t) { return m.l + (tMax === tMin ? 0 : (t - tMin) / (tMax - tMin)) * (width - m.l - m.r); };
      var Y = function (v) { return m.t + (1 - (v - vMin) / ((vMax - vMin) || 1)) * (height - m.t - m.b); };

      var svg = svgEl("svg", { viewBox: "0 0 " + width + " " + height, height: height, role: "img", "aria-label": opts.label || "graphique" });
      ticks.forEach(function (v) {
        svgEl("line", { x1: m.l, x2: width - m.r, y1: Y(v), y2: Y(v), "class": v === 0 && opts.zeroBaseline ? "baseline" : "gridline" }, svg);
        var tx = svgEl("text", { x: m.l - 8, y: Y(v) + 4, "text-anchor": "end", "class": "tick" }, svg);
        tx.textContent = opts.format(v, true);
      });
      svgEl("line", { x1: m.l, x2: width - m.r, y1: height - m.b, y2: height - m.b, "class": "baseline" }, svg);
      var nx = Math.max(2, Math.min(6, Math.floor((width - m.l - m.r) / 110)));
      for (var i = 0; i <= nx; i++) {
        var t = tMin + (i / nx) * (tMax - tMin);
        var lab = svgEl("text", { x: X(t), y: height - 8, "text-anchor": i === 0 ? "start" : i === nx ? "end" : "middle", "class": "tick" }, svg);
        lab.textContent = opts.dateFormat(t, tMax - tMin);
      }
      var base = opts.zeroBaseline ? Y(0) : height - m.b;
      series.forEach(function (s) {
        var d = s.points.map(function (p, k) { return (k ? "L" : "M") + X(p.t).toFixed(1) + " " + Y(p.v).toFixed(1); }).join(" ");
        if (s.area) {
          var first = s.points[0], last = s.points[s.points.length - 1];
          svgEl("path", { d: d + " L" + X(last.t).toFixed(1) + " " + base + " L" + X(first.t).toFixed(1) + " " + base + " Z", "class": "area-" + s.cls }, svg);
        }
        svgEl("path", { d: d, "class": "line " + s.cls }, svg);
      });
      // End dots + direct end labels (sparing: last value only), nudged apart if they collide.
      var ends = series.map(function (s) { var p = s.points[s.points.length - 1]; return { s: s, p: p, y: Y(p.v) }; });
      ends.sort(function (a, b) { return a.y - b.y; });
      for (var k = 1; k < ends.length; k++) if (ends[k].y - ends[k - 1].y < 14) ends[k].y = ends[k - 1].y + 14;
      ends.forEach(function (e) {
        svgEl("circle", { cx: X(e.p.t), cy: Y(e.p.v), r: 4, "class": "dot-" + e.s.cls }, svg);
        var lt = svgEl("text", { x: X(e.p.t) + 8, y: e.y + 4, "class": "endlabel" }, svg);
        lt.textContent = opts.format(e.p.v, true);
      });

      // Hover / keyboard layer
      var cross = svgEl("line", { y1: m.t, y2: height - m.b, "class": "crosshair", visibility: "hidden" }, svg);
      var hit = svgEl("rect", { x: m.l, y: m.t, width: width - m.l - m.r, height: height - m.t - m.b, fill: "transparent", tabindex: 0, "aria-label": "Parcourir les valeurs avec les flèches" }, svg);
      container.appendChild(svg);
      var tip = htmlEl("div", "tooltip hidden");
      container.appendChild(tip);
      var ref = series[0].points, idx = ref.length - 1;
      function nearest(arr, t) {
        var lo = 0, hi = arr.length - 1;
        while (hi - lo > 1) { var mid = (lo + hi) >> 1; if (arr[mid].t < t) lo = mid; else hi = mid; }
        return Math.abs(arr[lo].t - t) <= Math.abs(arr[hi].t - t) ? lo : hi;
      }
      function show(i) {
        idx = Math.max(0, Math.min(ref.length - 1, i));
        var t = ref[idx].t, x = X(t);
        cross.setAttribute("x1", x); cross.setAttribute("x2", x); cross.setAttribute("visibility", "visible");
        tip.textContent = "";
        tip.appendChild(htmlEl("div", "t", opts.dateFormat(t, 0, true)));
        series.forEach(function (s) {
          var p = s.points[nearest(s.points, t)];
          var row = htmlEl("div", "row");
          var key = htmlEl("span", "key"); key.classList.add(s.cls === "s2" ? "k2" : "k1");
          if (s.cls === "neg") key.style.background = "var(--negative)";
          row.appendChild(key);
          row.appendChild(htmlEl("strong", "", opts.format(p.v)));
          row.appendChild(htmlEl("span", "", s.name));
          tip.appendChild(row);
        });
        tip.classList.remove("hidden");
        var scale = container.clientWidth / width;
        var left = x * scale + 12;
        if (left + tip.offsetWidth > container.clientWidth) left = x * scale - tip.offsetWidth - 12;
        tip.style.left = Math.max(0, left) + "px";
        tip.style.top = "8px";
      }
      function hide() { cross.setAttribute("visibility", "hidden"); tip.classList.add("hidden"); }
      hit.addEventListener("pointermove", function (ev) {
        var r = svg.getBoundingClientRect();
        var xv = (ev.clientX - r.left) * (width / r.width);
        var t = tMin + ((xv - m.l) / (width - m.l - m.r)) * (tMax - tMin);
        show(nearest(ref, t));
      });
      hit.addEventListener("pointerleave", hide);
      hit.addEventListener("blur", hide);
      hit.addEventListener("focus", function () { show(idx); });
      hit.addEventListener("keydown", function (ev) {
        if (ev.key === "ArrowLeft") { show(idx - 1); ev.preventDefault(); }
        else if (ev.key === "ArrowRight") { show(idx + 1); ev.preventDefault(); }
        else if (ev.key === "Escape") hide();
      });
    });
  }

  /* ---------------- horizontal diverging bars ---------------- */
  function barPath(x0, x1, y, h) {
    var w = Math.abs(x1 - x0), r = Math.min(4, w / 2, h / 2), dir = x1 >= x0 ? 1 : -1;
    if (w < 0.5) return "";
    return "M" + x0 + " " + y + " H" + (x1 - dir * r) + " Q" + x1 + " " + y + " " + x1 + " " + (y + r) +
      " V" + (y + h - r) + " Q" + x1 + " " + (y + h) + " " + (x1 - dir * r) + " " + (y + h) + " H" + x0 + " Z";
  }

  function bars(container, opts) {
    observe(container, function () {
      container.textContent = "";
      var items = opts.items || [];
      var rowH = 34, barH = 18, height = Math.max(120, items.length * rowH + 16);
      if (!items.length) { emptyState(container, 160, opts.emptyText || "Aucun bot"); return; }
      var width = Math.max(280, container.clientWidth || 500);
      var labelW = Math.min(150, width * 0.35), m = { l: labelW + 8, r: 16 };
      var maxAbs = Math.max.apply(null, items.map(function (d) { return Math.abs(d.value); })) || 1;
      var hasNeg = items.some(function (d) { return d.value < 0; });
      var valueRoom = 70;
      var plotL = m.l + (hasNeg ? valueRoom : 0), plotR = width - m.r - valueRoom;
      var zero = hasNeg ? (plotL + plotR) / 2 : plotL;
      var scale = (hasNeg ? (plotR - plotL) / 2 : plotR - plotL) / maxAbs;
      var svg = svgEl("svg", { viewBox: "0 0 " + width + " " + height, height: height, role: "img", "aria-label": opts.label || "barres" });
      svgEl("line", { x1: zero, x2: zero, y1: 4, y2: height - 4, "class": "baseline" }, svg);
      var tip = htmlEl("div", "tooltip hidden");
      items.forEach(function (d, i) {
        var y = 8 + i * rowH + (rowH - barH) / 2;
        var name = d.label.length > 18 ? d.label.slice(0, 17) + "…" : d.label;
        var lt = svgEl("text", { x: 0, y: y + barH / 2 + 4, "class": "label" }, svg);
        lt.textContent = name;
        var x1 = zero + d.value * scale;
        var hitR = svgEl("rect", { x: 0, y: 8 + i * rowH, width: width, height: rowH, "class": "bar-hit", tabindex: 0 }, svg);
        var p = barPath(zero, x1, y, barH);
        if (p) svgEl("path", { d: p, "class": d.value >= 0 ? "bar-pos" : "bar-neg" }, svg);
        var vt = svgEl("text", { x: d.value >= 0 ? x1 + 6 : x1 - 6, y: y + barH / 2 + 4, "text-anchor": d.value >= 0 ? "start" : "end", "class": "value" }, svg);
        vt.textContent = opts.format(d.value);
        function show() {
          tip.textContent = "";
          tip.appendChild(htmlEl("div", "t", d.label));
          var row = htmlEl("div", "row"); row.appendChild(htmlEl("strong", "", opts.format(d.value)));
          if (d.detail) row.appendChild(htmlEl("span", "", d.detail));
          tip.appendChild(row);
          tip.classList.remove("hidden");
          tip.style.left = "8px"; tip.style.top = (y + barH + 6) * (container.clientWidth / width) + "px";
        }
        hitR.addEventListener("pointerenter", show);
        hitR.addEventListener("focus", show);
        hitR.addEventListener("pointerleave", function () { tip.classList.add("hidden"); });
        hitR.addEventListener("blur", function () { tip.classList.add("hidden"); });
      });
      container.appendChild(svg);
      container.appendChild(tip);
    });
  }

  window.Charts = { line: line, bars: bars };
})();
