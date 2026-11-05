# The twin world: a 2D pixel view of the business as a Minecraft-style
# inventory map. Renders twin.representations into:
#
#   packages.twin-world         world.json + twin.html (self-contained)
#   checks.twin-world           Lean proving the twin facts
#   checks.twin-view            chromium screenshots twin.html + deep-link test
#
# world.json: districts, representations with sprites, recipes, agents
# twin.html:   a canvas with nearest-neighbour pixel rendering, tap/click
#              panel, search box, mobile-first at 390px, dark mode
{ lib, config, ... }:
let
  cfg = config.twin;
  q = builtins.toJSON;

  # ── build the world data ─────────────────────────────────────────────
  # The data that powers both the HTML and JSON.
  districts = lib.mapAttrsToList (n: d: { name = n; } // d) cfg.districts;
  sortedDistricts = lib.sort (a: b: a.order < b.order) districts;

  # District colour lookup for the legend swatches.

  # Load sprite: use the explicit sprite or a default based on kind.
  defaultSpriteOf =
    kind:
    let
      # Default sprites (each 16 strings of 16 chars).
      house = [
        "0000000000000000"
        "0222222222222220"
        "0211111111111120"
        "0211111111111120"
        "0211144441111120"
        "0211111111111120"
        "0211111111111120"
        "0211111441111120"
        "0211111111111120"
        "0211122222111120"
        "0211111111111120"
        "0211111111111120"
        "0211111111111120"
        "0211111111111120"
        "0222222222222220"
        "0ff0000000000ff0"
      ];
      blank = builtins.genList (_: "0000000000000000") 16;
    in
    {
      building = house;
      character = blank;
      item = blank;
      block = blank;
    }
    .${kind};

  # Representations as a list for JSON, with sprites resolved.
  reps = lib.mapAttrsToList (n: r: {
    inherit n;
    inherit (r) kind place status;
    inherit (r.of)
      module
      account
      team
      asset
      ;
    sprite = if r.sprite != null then r.sprite else defaultSpriteOf r.kind;
    inherit (r) recipes;
  }) cfg.representations;

  # Agents with positions (empty for now, filled by JS runtime state).
  agentList = lib.mapAttrsToList (n: a: {
    inherit n;
    inherit (a) serves;
    building = null; # resolved at runtime via window.__twinState
    lastMessage = null;
    spendUsd = null;
  }) config.governance.agents;

  # ── world.json ───────────────────────────────────────────────────────
  worldJson = builtins.toJSON {
    districts = sortedDistricts;
    representations = reps;
    agents = agentList;
    inherit (cfg) palette;
    saves = { };
  };

  # ── twin.html ────────────────────────────────────────────────────────
  html = ''
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <title>Digital Twin World</title>
    <style>
      :root {
        --bg:#fbfaf8; --card:#ffffff; --fg:#1d1c1a; --muted:#6b6862;
        --line:#e4e1db; --accent:#2b5fa8; --gap:#b4441f; --ok:#2f6f4f;
      }
      @media (prefers-color-scheme: dark) {
        :root { --bg:#151514; --card:#1e1e1c; --fg:#ecebe8; --muted:#a3a09a; --line:#34322f; --accent:#8db4ee; --gap:#ef8a64; --ok:#7fc4a0; }
      }
      * { box-sizing:border-box; }
      body { background:var(--bg); color:var(--fg); font:14px/1.4 system-ui,sans-serif; margin:0; padding:0; overscroll-behavior:none; height:100dvh; width:100vw; }
      #app { display:flex; flex-direction:column; height:100dvh; }
      header { display:flex; align-items:center; gap:8px; padding:6px 10px; border-bottom:1px solid var(--line); flex-shrink:0; }
      header h1 { font-size:16px; margin:0; white-space:nowrap; }
      #search { flex:1; border:1px solid var(--line); border-radius:6px; padding:6px 10px; background:var(--card); color:var(--fg); font-size:14px; min-width:0; }
      #search:focus { outline:none; border-color:var(--accent); }
      /* ── legend chip row ───────────────────────────────────── */
      #chip-row { display:flex; flex-wrap:wrap; align-items:center; gap:4px 6px; padding:4px 10px; border-bottom:1px solid var(--line); flex-shrink:0; min-height:32px; }
      #chip-row .chip-toggle { background:none; border:none; color:var(--muted); cursor:pointer; font-size:12px; font-weight:600; padding:2px 6px; border-radius:4px; display:flex; align-items:center; gap:4px; }
      #chip-row .chip-toggle:hover { background:var(--line); }
      #chip-row .chip-toggle .arrow { transition:transform .2s; display:inline-block; }
      #chip-row .chip-toggle.collapsed .arrow { transform:rotate(-90deg); }
      #chip-row .chip-body { display:flex; flex-wrap:wrap; gap:4px 6px; }
      #chip-row .chip-body.collapsed { display:none; }
      #chip-row .chip { display:inline-flex; align-items:center; gap:4px; font-size:11px; font-weight:600; padding:2px 10px 2px 6px; border-radius:12px; cursor:pointer; border:1px solid transparent; transition:border-color .15s; }
      #chip-row .chip:hover { border-color:var(--accent); }
      .chip-swatch { width:10px; height:10px; border-radius:2px; flex-shrink:0; }
      /* ── world wrap ────────────────────────────────────────── */
      #world-wrap { flex:1; position:relative; overflow:hidden; touch-action:none; }
      #world-canvas { display:block; image-rendering:pixelated; image-rendering:crisp-edges; position:absolute; top:0; left:0; }
      /* ── fit button ────────────────────────────────────────── */
      #fit-btn { position:absolute; bottom:8px; right:8px; z-index:5; background:var(--card); border:1px solid var(--line); border-radius:6px; padding:4px 8px; font-size:11px; cursor:pointer; color:var(--fg); box-shadow:0 1px 4px rgba(0,0,0,.1); }
      #fit-btn:hover { border-color:var(--accent); }
      /* ── panel ─────────────────────────────────────────────── */
      #panel { position:fixed; bottom:0; left:0; right:0; max-height:70dvh; background:var(--card); border-top:2px solid var(--line); border-radius:12px 12px 0 0; padding:14px 16px 16px; overflow-y:auto; transform:translateY(100%); transition:transform .25s ease; z-index:10; box-shadow:0 -4px 20px rgba(0,0,0,.15); }
      #panel.open { transform:translateY(0); }
      #panel .panel-hdr { display:flex; align-items:center; gap:10px; margin-bottom:6px; }
      #panel .panel-hdr .sprite4x { width:64px; height:64px; image-rendering:pixelated; image-rendering:crisp-edges; border:1px solid var(--line); border-radius:4px; flex-shrink:0; }
      #panel .panel-hdr h2 { font-size:17px; margin:0; }
      #panel .close { margin-left:auto; background:none; border:none; color:var(--muted); font-size:22px; cursor:pointer; padding:0 4px; line-height:1; }
      #panel .sub { color:var(--muted); font-size:13px; margin-bottom:8px; }
      #panel .status { display:inline-block; font-size:11px; padding:2px 8px; border-radius:10px; }
      .status-declared { background:var(--line); color:var(--muted); }
      .status-running { background:var(--ok); color:#fff; }
      .status-paused { background:var(--accent); color:#fff; }
      .status-gap { background:var(--gap); color:#fff; }
      /* JEI-style recipe grid */
      .recipe-grid { display:flex; flex-wrap:wrap; gap:10px; margin:8px 0; }
      .recipe-card { background:var(--bg); border:1px solid var(--line); border-radius:6px; padding:8px; display:flex; align-items:center; gap:6px; font-size:12px; }
      .recipe-card .arrow { color:var(--muted); font-size:14px; padding:0 2px; }
      .recipe-tile { width:36px; height:36px; image-rendering:pixelated; image-rendering:crisp-edges; border:1px solid var(--line); border-radius:3px; display:inline-flex; align-items:center; justify-content:center; font-size:9px; overflow:hidden; position:relative; background:var(--card); }
      .recipe-tile img { width:100%; height:100%; object-fit:contain; }
      .recipe-tile .badge { position:absolute; bottom:0; right:0; font-size:8px; background:var(--card); padding:0 2px; border:1px solid var(--line); border-radius:2px; line-height:1.2; }
      .hint { color:var(--muted); font-size:13px; font-style:italic; }
      @media (min-width:800px) {
        #panel { left:auto; right:16px; bottom:16px; width:380px; max-height:80vh; border-radius:12px; border:1px solid var(--line); }
      }
    </style></head><body>
    <div id="app">
    <header>
      <h1>🌍 Twin</h1>
      <input id="search" type="search" placeholder="Search modules, agents, items…" autocomplete="off">
    </header>
    <div id="chip-row"></div>
    <div id="world-wrap">
      <canvas id="world-canvas"></canvas>
      <button id="fit-btn">⌂ Fit</button>
    </div>
    </div>
    <div id="panel"></div>
    <script>
    (function(){
      "use strict";

      // -- world data -------------------------------------------
      const world = ${worldJson};
      const pal = world.palette || {};
      const repByName = {};
      world.representations.forEach(function(r) { repByName[r.n] = r; });
      const districts = world.districts;

      // -- dom refs ---------------------------------------------
      var canvas = document.getElementById("world-canvas");
      var wrap = document.getElementById("world-wrap");
      var panel = document.getElementById("panel");
      var search = document.getElementById("search");
      var chipRow = document.getElementById("chip-row");
      var fitBtn = document.getElementById("fit-btn");

      var SPR = 16;

      // -- pan / scroll state ------------------------------------
      var panX = 0;
      var panY = 0;

      // -- build map data ---------------------------------------
      function buildMap() {
        var byDist = {};
        world.representations.forEach(function(r) {
          if (!byDist[r.place]) byDist[r.place] = [];
          byDist[r.place].push(r);
        });
        return districts.map(function(d) {
          var reps = byDist[d.name] || [];
          reps.sort(function(a,b) {
            var o = {building:0, character:1, item:2, block:3};
            return (o[a.kind]||9) - (o[b.kind]||9);
          });
          var n = reps.length;
          var cols = Math.max(1, Math.ceil(Math.sqrt(n)));
          var rows = Math.ceil(n / cols);
          reps.forEach(function(r, i) {
            r._gx = (i % cols) * SPR;
            r._gy = Math.floor(i / cols) * SPR;
          });
          return { d: d, reps: reps, cols: cols, rows: rows };
        });
      }
      var mapData = buildMap();

      // -- draw a sprite onto a canvas context ------------------
      function drawSprite(ctx, sprite, x, y, sc, dim) {
        if (!sprite || !sprite.length) return;
        var sz = SPR * sc;
        var osc = document.createElement("canvas");
        osc.width = sz; osc.height = sz;
        var octx = osc.getContext("2d");
        octx.imageSmoothingEnabled = false;
        for (var row = 0; row < SPR; row++) {
          var line = sprite[row];
          if (!line) continue;
          for (var col = 0; col < SPR; col++) {
            var ch = line[col];
            if (ch && ch !== "0") {
              octx.fillStyle = pal[ch] || "#000";
              octx.fillRect(col * sc, row * sc, sc, sc);
            }
          }
        }
        ctx.imageSmoothingEnabled = false;
        if (dim) ctx.globalAlpha = 0.25;
        ctx.drawImage(osc, x, y);
        ctx.globalAlpha = 1.0;
      }

      // -- render sprite to data URL at 4x ----------------------
      function spriteDataURL(sprite, mult) {
        if (!sprite || !sprite.length) return "";
        var m = mult || 4;
        var sz = SPR * m;
        var osc = document.createElement("canvas");
        osc.width = sz; osc.height = sz;
        var octx = osc.getContext("2d");
        octx.imageSmoothingEnabled = false;
        for (var row = 0; row < SPR; row++) {
          var line = sprite[row];
          if (!line) continue;
          for (var col = 0; col < SPR; col++) {
            var ch = line[col];
            if (ch && ch !== "0") {
              octx.fillStyle = pal[ch] || "#000";
              octx.fillRect(col * m, row * m, m, m);
            }
          }
        }
        return osc.toDataURL();
      }

      // -- compute grid columns from viewport width -------------
      function gridCols(vw) {
        if (vw < 480) return 1;
        if (vw < 900) return 2;
        return 3;
      }

      // -- render -----------------------------------------------
      function render() {
        var rect = wrap.getBoundingClientRect();
        var vw = rect.width;
        var vh = rect.height;
        var spriteScale = vw >= 600 ? 3 : 2;
        var tilePx = SPR * spriteScale;
        var GAP = Math.round(SPR * spriteScale * 0.35);

        var nCols = gridCols(vw);
        var colW = Math.floor((vw - (nCols - 1) * GAP) / nCols);

        var distLayout = [];
        var curCol = 0;
        var curY = 0;
        var colH = new Array(nCols).fill(0);

        var cellPad = Math.round(SPR * spriteScale * 0.2);

        mapData.forEach(function(md, idx) {
          var nRep = md.reps.length;
          var repCols = md.cols;
          var repRows = md.rows;
          var w = repCols * tilePx + cellPad * 2;
          var h = repRows * tilePx;
          var labH = Math.round(SPR * spriteScale * 0.75);
          var totalH = labH + h + Math.round(SPR * spriteScale * 0.25) + cellPad * 2;
          var cellW = Math.min(colW, w + GAP);

          // find the shortest column
          var minCol = 0;
          var minH = colH[0];
          for (var c = 1; c < nCols; c++) {
            if (colH[c] < minH) { minH = colH[c]; minCol = c; }
          }
          curCol = minCol;
          curY = colH[curCol];

          var x = curCol * (colW + GAP) + Math.floor((colW - cellW) / 2);
          if (x < 0) x = 0;

          distLayout.push({
            md: md, x: x, y: curY, w: w, h: h, labH: labH, totalH: totalH,
            groundW: cellW,
            groundH: totalH,
            col: curCol
          });

          colH[curCol] = curY + totalH + GAP;
        });

        var mapH = Math.max.apply(null, colH);
        var mapW = nCols * (colW + GAP) - GAP;
        if (mapW < vw) mapW = vw;

        canvas.width = Math.ceil(mapW);
        canvas.height = Math.ceil(mapH);
        canvas.style.width = Math.ceil(mapW) + "px";
        canvas.style.height = Math.ceil(mapH) + "px";

        var offX = panX;
        var offY = panY;
        canvas.style.left = offX + "px";
        canvas.style.top = offY + "px";

        var ctx = canvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;
        var isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

        distLayout.forEach(function(dl) {
          var gx = dl.x, gy = dl.y;
          var d = dl.md.d;
          var groundCol = isDark ? d.color.dark : d.color.light;
          ctx.fillStyle = groundCol;
          ctx.fillRect(gx, gy, dl.groundW, dl.groundH);
          ctx.fillStyle = isDark ? "#ecebe8" : "#1d1c1a";
          ctx.font = "900 " + Math.round(SPR * spriteScale * 0.5) + "px system-ui,sans-serif";
          ctx.textBaseline = "top";
          ctx.fillText(d.label, gx + cellPad, gy + cellPad);
          dl.md.reps.forEach(function(r) {
            var sx = gx + cellPad + r._gx * spriteScale;
            var sy = gy + (dl.labH + cellPad + r._gy * spriteScale);
            drawSprite(ctx, r.sprite, sx, sy, spriteScale, r._filtered);
          });
        });

        // -- legend chip row -------------------------------------
        chipRow.innerHTML =
          '<button class="chip-toggle" id="chip-toggle">' +
          '<span class="arrow">▼</span> Districts</button>' +
          '<div class="chip-body" id="chip-body">' +
          districts.map(function(d) {
            var col = isDark ? d.color.dark : d.color.light;
            return '<span class="chip" data-dist="' + d.name + '"><span class="chip-swatch" style="background:' + col + '"></span>' + d.label + '</span>';
          }).join("") +
          '</div>';

        var toggleBtn = document.getElementById("chip-toggle");
        var chipBody = document.getElementById("chip-body");
        toggleBtn.addEventListener("click", function() {
          chipBody.classList.toggle("collapsed");
          toggleBtn.classList.toggle("collapsed");
        });
        chipBody.querySelectorAll(".chip").forEach(function(el) {
          el.addEventListener("click", function() {
            var distName = el.getAttribute("data-dist");
            var dl = distLayout.find(function(d) { return d.md.d.name === distName; });
            if (dl) {
              panTo(dl.x, dl.y);
            }
          });
        });

        if (search.value.trim()) applyFilter(search.value.trim());

        window.__distLayout = distLayout;
        window.__spriteScale = spriteScale;
        window.__canvasOffX = offX;
        window.__canvasOffY = offY;
      }

      // -- pan to a district ------------------------------------
      var panAnim = null;
      function panTo(tx, ty) {
        if (panAnim) { cancelAnimationFrame(panAnim); panAnim = null; }
        var rect = wrap.getBoundingClientRect();
        var vw = rect.width;
        var vh = rect.height;
        var startX = panX;
        var startY = panY;
        // centre the target
        var targetX = -tx + Math.floor(vw / 2);
        var targetY = -ty + Math.floor(vh / 2);
        // clamp so canvas doesn't leave viewport
        var cw = parseInt(canvas.style.width);
        var ch = parseInt(canvas.style.height);
        if (targetX > 0) targetX = 0;
        if (targetY > 0) targetY = 0;
        if (targetX < -(cw - vw)) targetX = -(cw - vw);
        if (targetY < -(ch - vh)) targetY = -(ch - vh);
        if (cw <= vw) targetX = 0;
        if (ch <= vh) targetY = 0;

        var dur = 250;
        var t0 = performance.now();
        function step(now) {
          var t = Math.min(1, (now - t0) / dur);
          var ease = t < 0.5 ? 2*t*t : -1 + (4-2*t)*t; // easeInOutQuad
          panX = startX + (targetX - startX) * ease;
          panY = startY + (targetY - startY) * ease;
          canvas.style.left = Math.round(panX) + "px";
          canvas.style.top = Math.round(panY) + "px";
          if (t < 1) { panAnim = requestAnimationFrame(step); }
          else { panAnim = null; }
        }
        panAnim = requestAnimationFrame(step);
      }

      // -- fit --------------------------------------------------
      function fitView() {
        panX = 0;
        panY = 0;
        canvas.style.left = "0px";
        canvas.style.top = "0px";
        initDrag();
        render();
      }

      fitBtn.addEventListener("click", fitView);

      // -- search / filter --------------------------------------
      function applyFilter(q) {
        var lowerQ = q.toLowerCase();
        var matches = [];
        world.representations.forEach(function(r) {
          var match = r.n.toLowerCase().indexOf(lowerQ) !== -1 ||
            r.place.toLowerCase().indexOf(lowerQ) !== -1 ||
            r.kind.toLowerCase().indexOf(lowerQ) !== -1 ||
            (r.module && r.module.toLowerCase().indexOf(lowerQ) !== -1) ||
            (r.team && r.team.toLowerCase().indexOf(lowerQ) !== -1);
          r._filtered = !match;
          if (match) matches.push(r);
        });

        var spriteScale = window.__spriteScale || 2;
        var isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
        var distLayout = window.__distLayout;
        var cellPad = Math.round(SPR * spriteScale * 0.2);
        if (!distLayout) return;

        var ctx = canvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;

        distLayout.forEach(function(dl) {
          var gx = dl.x, gy = dl.y;
          var d = dl.md.d;
          var groundCol = isDark ? d.color.dark : d.color.light;
          ctx.fillStyle = groundCol;
          ctx.fillRect(gx, gy, dl.groundW, dl.groundH);
          ctx.fillStyle = isDark ? "#ecebe8" : "#1d1c1a";
          ctx.font = "900 " + Math.round(SPR * spriteScale * 0.5) + "px system-ui,sans-serif";
          ctx.textBaseline = "top";
          ctx.fillText(d.label, gx + cellPad, gy + cellPad);
          dl.md.reps.forEach(function(r) {
            var sx = gx + cellPad + r._gx * spriteScale;
            var sy = gy + (dl.labH + cellPad + r._gy * spriteScale);
            drawSprite(ctx, r.sprite, sx, sy, spriteScale, r._filtered);
          });
        });

        if (matches.length > 0) {
          var first = matches[0];
          var dl = distLayout.find(function(dl) { return dl.md.d.name === first.place; });
          if (dl) {
            var sx = dl.x + cellPad + first._gx * spriteScale;
            var sy = dl.y + (dl.labH + cellPad + first._gy * spriteScale);
            ctx.strokeStyle = isDark ? "#f0c040" : "#d4a017";
            ctx.lineWidth = 3;
            ctx.strokeRect(sx - 2, sy - 2, SPR * spriteScale + 4, SPR * spriteScale + 4);
          }
        }
      }

      search.addEventListener("input", function() {
        var q = this.value.trim();
        if (!q) {
          world.representations.forEach(function(r) { r._filtered = false; });
          render();
          return;
        }
        applyFilter(q);
      });

      // -- panel -------------------------------------------------
      var selected = null;
      function openPanel(r) {
        selected = r;
        var kindIcon = { building:"🏢", item:"💎", block:"🧱", character:"🧑" };
        var icon = kindIcon[r.kind] || "📦";
        var what = r.module || r.team || r.account || r.asset || "-";
        var whatLabel = r.module ? "Module" : r.team ? "Team" : r.account ? "Account" : "Asset";
        var dataUrl = spriteDataURL(r.sprite, 4);

        var hdr = '<div class="panel-hdr">';
        if (dataUrl) {
          hdr += '<img class="sprite4x" src="' + dataUrl + '" alt="">';
        } else {
          hdr += '<div class="sprite4x" style="display:flex;align-items:center;justify-content:center;font-size:28px">' + icon + '</div>';
        }
        hdr += '<h2>' + r.n + '</h2>';
        hdr += '<button class="close" onclick="document.getElementById(\'panel\').classList.remove(\'open\')">\u2715</button>';
        hdr += '</div>';

        panel.innerHTML = hdr +
          '<div class="sub">' + r.kind + ' &mdash; ' + whatLabel + ': ' + what + '</div>' +
          '<span class="status status-' + r.status + '">' + r.status + '</span>' +
          '<div style="margin:8px 0 0"><strong>District:</strong> ' + r.place + '</div>';

        if (r.recipes && r.recipes.length) {
          panel.innerHTML += '<div style="margin:10px 0 4px;font-size:13px;font-weight:600">Recipes</div>';
          panel.innerHTML += '<div class="recipe-grid">';
          r.recipes.forEach(function(rec) {
            panel.innerHTML += '<div class="recipe-card">';
            if (rec.inputs && rec.inputs.length) {
              rec.inputs.forEach(function(inp) {
                var tr = repByName[inp];
                var tu = tr && tr.sprite ? spriteDataURL(tr.sprite, 2) : "";
                panel.innerHTML += '<div class="recipe-tile"' +
                  (tu ? ' style="background-image:url(' + tu + ');background-size:contain"' : "") +
                  ' title="' + inp + '">' +
                  (!tu ? inp.slice(0,3) : "") + '</div>';
              });
            }
            panel.innerHTML += '<span class="arrow">\u2192</span>';
            if (rec.outputs && rec.outputs.length) {
              rec.outputs.forEach(function(out) {
                var tr = repByName[out];
                var tu = tr && tr.sprite ? spriteDataURL(tr.sprite, 2) : "";
                panel.innerHTML += '<div class="recipe-tile"' +
                  (tu ? ' style="background-image:url(' + tu + ');background-size:contain"' : "") +
                  ' title="' + out + '">' +
                  (!tu ? out.slice(0,3) : "") + '</div>';
              });
            }
            panel.innerHTML += '</div>';
          });
          panel.innerHTML += '</div>';
        } else {
          panel.innerHTML += '<p class="hint" style="margin-top:10px">No recipes declared for this ' + r.kind + '.</p>';
        }

        panel.classList.add("open");
      }

      // -- hit testing -------------------------------------------
      function hitTest(cx, cy) {
        var rect = wrap.getBoundingClientRect();
        var mapX = cx - rect.left;
        var mapY = cy - rect.top;
        var dl = window.__distLayout;
        var sc = window.__spriteScale || 2;
        var ox = window.__canvasOffX || 0;
        var oy = window.__canvasOffY || 0;
        var cellPad = Math.round(SPR * sc * 0.2);
        var cx2 = mapX - ox;
        var cy2 = mapY - oy;
        if (!dl) return null;
        for (var i = 0; i < dl.length; i++) {
          var d = dl[i];
          if (cx2 >= d.x && cx2 < d.x + d.groundW && cy2 >= d.y && cy2 < d.y + d.groundH) {
            for (var j = 0; j < d.md.reps.length; j++) {
              var r = d.md.reps[j];
              var sx = d.x + cellPad + r._gx * sc;
              var sy = d.y + (d.labH + cellPad + r._gy * sc);
              if (cx2 >= sx && cx2 < sx + SPR * sc && cy2 >= sy && cy2 < sy + SPR * sc) {
                return r;
              }
            }
          }
        }
        return null;
      }

      // -- mouse events ------------------------------------------
      var dragState = null;
      function initDrag() {
        dragState = null;
      }

      wrap.addEventListener("mousedown", function(e) {
        dragState = { startX: e.clientX, startY: e.clientY, startPanX: panX, startPanY: panY, moved: false };
      });
      window.addEventListener("mousemove", function(e) {
        if (!dragState) return;
        var dx = e.clientX - dragState.startX;
        var dy = e.clientY - dragState.startY;
        if (Math.abs(dx) > 4 || Math.abs(dy) > 4) {
          dragState.moved = true;
          panX = dragState.startPanX + dx;
          panY = dragState.startPanY + dy;
          canvas.style.left = panX + "px";
          canvas.style.top = panY + "px";
        }
      });
      window.addEventListener("mouseup", function(e) {
        if (!dragState) return;
        var was = dragState.moved;
        dragState = null;
        if (!was) {
          var hit = hitTest(e.clientX, e.clientY);
          if (hit) openPanel(hit);
        }
      });

      // -- touch events ------------------------------------------
      var touchState = null;
      wrap.addEventListener("touchstart", function(e) {
        if (e.touches.length === 1) {
          touchState = { startX: e.touches[0].clientX, startY: e.touches[0].clientY, startPanX: panX, startPanY: panY, moved: false };
        }
      }, { passive: true });
      wrap.addEventListener("touchmove", function(e) {
        if (e.touches.length === 1 && touchState) {
          var dx = e.touches[0].clientX - touchState.startX;
          var dy = e.touches[0].clientY - touchState.startY;
          if (Math.abs(dx) > 8 || Math.abs(dy) > 8) touchState.moved = true;
          panX = touchState.startPanX + dx;
          panY = touchState.startPanY + dy;
          canvas.style.left = panX + "px";
          canvas.style.top = panY + "px";
        }
      }, { passive: true });
      wrap.addEventListener("touchend", function(e) {
        if (touchState) {
          var was = touchState.moved;
          if (!was && e.changedTouches.length > 0) {
            var hit = hitTest(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
            if (hit) openPanel(hit);
          }
          touchState = null;
        }
      }, { passive: true });

      // -- __twinState runtime ------------------------------------
      if (window.__twinState) {
        var st = window.__twinState;
        if (st.agents) {
          Object.keys(st.agents).forEach(function(name) {
            var a = st.agents[name];
            var info = document.createElement("div");
            info.style.cssText = "position:absolute;bottom:8px;left:8px;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font-size:11px;z-index:5;";
            info.innerHTML = "<b>" + name + "</b>" +
              (a.lastMessage ? "<br>" + a.lastMessage : "") +
              (a.spendUsd != null ? "<br>$" + a.spendUsd.toFixed(2) + " spent" : "");
            wrap.appendChild(info);
          });
        }
      }

      // -- dark mode listener -------------------------------------
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function() { render(); });

      // -- init ---------------------------------------------------
      render();
      window.addEventListener("resize", render);

      // -- deep-link support --------------------------------------
      (function() {
        var params = new URLSearchParams(window.location.search);
        var n = params.get("open");
        if (n && repByName[n]) openPanel(repByName[n]);
      })();

    })();
    </script>
    </body></html>
  '';

  # ── checks ──────────────────────────────────────────────────────────
  # Build the full Check.lean: Types.lean (types, predicates, and lemmas
  # quantified over individual parameters) followed by the rendered facts
  # and the all-theorems, all inside a single namespace block.
  typesFile = builtins.readFile ./_lean/Types.lean;
  renderedCheck = ''
    ${typesFile}

    /-- Every representation, rendered by modules/twin/declarations.nix + options.nix. -/
    def representations : List Representation := [
    ${lib.concatMapStringsSep ",\n" (
      r:
      let
        ofModule = if r.module == null then "none" else "some ${q r.module}";
        ofAccount = if r.account == null then "none" else "some ${q r.account}";
        ofTeam = if r.team == null then "none" else "some ${q r.team}";
        ofAsset = if r.asset == null then "none" else "some ${q r.asset}";
        spriteStr = "some { rows := [${lib.concatMapStringsSep ", " q r.sprite}] }";
        kindMap = {
          building = "Kind.building";
          item = "Kind.item";
          block = "Kind.block";
          character = "Kind.character";
        };
      in
      "  { name := ${q r.n}, kind := ${kindMap.${r.kind}}, of := { mod := ${ofModule}, account := ${ofAccount}, team := ${ofTeam}, asset := ${ofAsset} }, sprite := ${spriteStr}, place := ${q r.place}, recipes := [${
          lib.concatMapStringsSep ", " (
            rc:
            "  { action := ${q rc.action}, inputs := [${lib.concatMapStringsSep ", " (builtins.map q rc.inputs)}], outputs := [${lib.concatMapStringsSep ", " (builtins.map q rc.outputs)}] }"
          ) r.recipes
        }], status := ${q r.status} }"
    ) reps}
    ]

    /-- The districts, rendered by the same. -/
    def districts : List (String × District) := [
    ${lib.concatMapStringsSep ",\n" (
      d:
      "  (${q d.name}, { label := ${q d.label}, order := ${toString d.order}, color := { light := ${q d.color.light}, dark := ${q d.color.dark} } })"
    ) sortedDistricts}
    ]

    /-- The governance action names that exist. -/
    def governanceActions : List String := [
    ${lib.concatMapStringsSep ",\n" (a: "  ${q a}") (
      lib.concatLists (
        lib.mapAttrsToList (
          provider: as: lib.mapAttrsToList (name: _: "${provider}:${name}") as
        ) config.governance.actions
      )
    )}
    ]

    /-- The perf-target module names. -/
    def perfModules : List String := [
    ${lib.concatMapStringsSep ",\n" (m: "  ${q m}") (
      lib.unique (map (t: t.module) (lib.attrValues config.perf.targets))
    )}
    ]

    /-- The agent names. -/
    def agents : List String := [
    ${lib.concatMapStringsSep ",\n" (n: "  ${q n}") (lib.attrNames config.governance.agents)}
    ]

    /-- Every perf-target module has exactly one building. -/
    theorem all_modules_have_buildings :
        perfModules.all (moduleHasBuilding representations) = true := by
      decide +kernel

    /-- Every agent has exactly one character. -/
    theorem all_agents_have_characters :
        agents.all (agentHasCharacter representations) = true := by
      decide +kernel

    /-- Every representation's district is declared. -/
    theorem all_places_declared :
        representations.all (fun r => r.placeDeclared districts) = true := by
      decide +kernel

    /-- Every representation's sprite is null or valid 16×16. -/
    theorem all_sprites_valid :
        representations.all Representation.spriteValid = true := by
      decide +kernel

    /-- Every recipe names a governance action that exists. -/
    theorem all_recipes_known :
        representations.all (fun r => r.recipesKnown governanceActions) = true := by
      decide +kernel

    end Kagamizo.Twin
  '';

in
{
  config.perSystem =
    { pkgs, ... }:
    let
      worldJsonFile = pkgs.writeText "world.json" worldJson;
      htmlFile = pkgs.writeText "twin.html" html;

      # The first building name, used for deep-link test.
      firstBuilding =
        let
          buildings = lib.filter (r: r.kind == "building") reps;
          sorted = lib.sort (a: b: a.n < b.n) buildings;
        in
        if builtins.length sorted > 0 then (builtins.head sorted).n else "building-tokens";
    in
    {
      packages.twin-world = pkgs.runCommand "twin-world" { } ''
        mkdir $out
        cp ${worldJsonFile} $out/world.json
        cp ${htmlFile} $out/twin.html
      '';

      checks.twin-world =
        pkgs.runCommand "twin-world"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            check = renderedCheck;
            passAsFile = [ "check" ];
          }
          ''
            cp "$checkPath" Check.lean
            lean Check.lean
            touch $out
          '';

      checks.twin-view =
        pkgs.runCommand "twin-view"
          {
            nativeBuildInputs = [ pkgs.chromium ];
          }
          ''
            export HOME=$TMPDIR
            mkdir $out

            # 1. Screenshot the world page on a phone-sized viewport.
            chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
              --window-size=390,844 --screenshot=$out/twin-phone.png \
              file://${htmlFile} 2>/dev/null
            test -s $out/twin-phone.png

            # 2. Deep-link test: ?open=<first building> must open the panel.
            #    chromium --dump-dom prints the rendered DOM; grep for the open class.
            chromium --headless=new --no-sandbox --disable-gpu \
              --dump-dom "file://${htmlFile}?open=${firstBuilding}" 2>/dev/null \
              | grep -q 'id="panel" class="open"'

            # 3. Copy the HTML into the output for inspection.
            cp ${htmlFile} $out/twin.html

            touch $out/panel-ok
          '';
    };
}
