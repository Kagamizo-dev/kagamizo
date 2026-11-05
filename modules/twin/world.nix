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

  # Load sprite: use the explicit sprite or a default based on kind.
  defaultSpriteOf = kind:
    let
      # Default sprites (each 16 strings of 16 chars).
      house = [
        "0000000000000000" "0222222222222220" "0211111111111120"
        "0211111111111120" "0211144441111120" "0211111111111120"
        "0211111111111120" "0211111441111120" "0211111111111120"
        "0211122222111120" "0211111111111120" "0211111111111120"
        "0211111111111120" "0211111111111120" "0222222222222220"
        "0ff0000000000ff0"
      ];
      blank = builtins.genList (_: "0000000000000000") 16;
    in
    {
      building = house;
      character = blank;
      item = blank;
      block = blank;
    }.${kind};

  # Representations as a list for JSON, with sprites resolved.
  reps = lib.mapAttrsToList (n: r: {
    inherit n;
    inherit (r) kind place status;
    inherit (r.of) module account team asset;
    sprite = if r.sprite != null then
      r.sprite
    else
      defaultSpriteOf r.kind;
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
    --tile:44;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#151514; --card:#1e1e1c; --fg:#ecebe8; --muted:#a3a09a; --line:#34322f; --accent:#8db4ee; --gap:#ef8a64; --ok:#7fc4a0; }
  }
  * { box-sizing:border-box; }
  body { background:var(--bg); color:var(--fg); font:14px/1.4 system-ui,sans-serif; margin:0; padding:0; overscroll-behavior:none; overflow:hidden; height:100dvh; width:100vw; }
  #app { display:flex; flex-direction:column; height:100dvh; }
  header { display:flex; align-items:center; gap:8px; padding:6px 10px; border-bottom:1px solid var(--line); flex-shrink:0; }
  header h1 { font-size:16px; margin:0; white-space:nowrap; }
  #search { flex:1; border:1px solid var(--line); border-radius:6px; padding:6px 10px; background:var(--card); color:var(--fg); font-size:14px; min-width:0; }
  #search:focus { outline:none; border-color:var(--accent); }
  #world-wrap { flex:1; position:relative; overflow:hidden; touch-action:none; }
  #world-canvas { display:block; image-rendering:pixelated; image-rendering:crisp-edges; }
  #panel { position:fixed; bottom:0; left:0; right:0; max-height:60dvh; background:var(--card); border-top:2px solid var(--line); border-radius:12px 12px 0 0; padding:12px 16px; overflow-y:auto; transform:translateY(100%); transition:transform .25s ease; z-index:10; box-shadow:0 -4px 20px rgba(0,0,0,.15); }
  #panel.open { transform:translateY(0); }
  #panel h2 { font-size:16px; margin:0 0 4px; }
  #panel .sub { color:var(--muted); font-size:13px; margin-bottom:8px; }
  #panel .close { float:right; background:none; border:none; color:var(--muted); font-size:20px; cursor:pointer; padding:0 4px; }
  #panel .recipe { background:var(--bg); border-radius:6px; padding:8px 10px; margin:6px 0; }
  #panel .recipe h3 { margin:0 0 2px; font-size:13px; }
  #panel .recipe p { margin:0; font-size:12px; color:var(--muted); }
  #panel .status { display:inline-block; font-size:11px; padding:2px 8px; border-radius:10px; }
  .status-declared { background:var(--line); color:var(--muted); }
  .status-running { background:var(--ok); color:#fff; }
  .status-paused { background:var(--accent); color:#fff; }
  .status-gap { background:var(--gap); color:#fff; }
  #legend { position:absolute; top:8px; right:8px; background:var(--card); border:1px solid var(--line); border-radius:8px; padding:6px 10px; font-size:11px; z-index:5; max-width:140px; }
  #legend b { display:block; margin-bottom:2px; }
  #legend span { display:inline-block; margin:1px 4px 1px 0; }
  .legend-b { width:10px;height:10px;display:inline-block;border-radius:2px;vertical-align:middle;margin-right:2px; }
  .district-label { font-size:10px; color:var(--muted); position:absolute; pointer-events:none; }
  @media (min-width:800px) {
    #panel { left:auto; right:16px; bottom:16px; width:360px; max-height:80vh; border-radius:12px; border:1px solid var(--line); }
  }
</style></head><body>
<div id="app">
<header>
  <h1>🌍 Twin</h1>
  <input id="search" type="search" placeholder="Search modules, agents, items…" autocomplete="off">
</header>
<div id="world-wrap">
  <canvas id="world-canvas"></canvas>
  <div id="legend"></div>
</div>
</div>
<div id="panel"></div>
<script>
(function(){
  'use strict';

  // ── world data ─────────────────────────────────────────────────────
  const world = ${worldJson};

  // Build palette map: char -> colour.
  const palette = world.palette || {};

  // The representations lookup: name -> rep
  const repByName = {};
  world.representations.forEach(r => { repByName[r.n] = r; });

  // The districts, sorted.
  const districts = world.districts;

  // ── canvas state ───────────────────────────────────────────────────
  const canvas = document.getElementById('world-canvas');
  const wrap = document.getElementById('world-wrap');
  const panel = document.getElementById('panel');
  const search = document.getElementById('search');
  const legend = document.getElementById('legend');

  const TILE = 44;          // px per tile at 1x
  const SPRITE_PX = 16;     // sprite is 16x16 "pixels"

  let scale = 1;
  let panX = 0, panY = 0;
  let dragging = false, dragStartX, dragStartY, panStartX, panStartY;
  let selected = null;

  // ── build the map ──────────────────────────────────────────────────
  function buildMap() {
    // Each district is a horizontal strip.
    // Layout: districts as columns, each as wide as its representations.
    const perDistrict = {};
    world.representations.forEach(r => {
      if (!perDistrict[r.place]) perDistrict[r.place] = [];
      perDistrict[r.place].push(r);
    });

    const cols = [];
    districts.forEach(d => {
      const reps = perDistrict[d.name] || [];
      // Sort: buildings first, then characters, then items/blocks.
      reps.sort((a,b) => {
        const o = {building:0, character:1, item:2, block:3};
        return (o[a.kind]||9) - (o[b.kind]||9);
      });
      cols.push({ district: d, reps });
    });

    // Calculate total grid size.
    let totalW = 0, maxH = 0;
    const colData = cols.map(c => {
      const n = c.reps.length;
      const w = Math.max(1, Math.ceil(Math.sqrt(n)));
      const h = Math.ceil(n / w);
      const cw = w * SPRITE_PX;
      const ch = h * SPRITE_PX;
      const x = totalW;
      totalW += cw + 4; // 4px gap
      maxH = Math.max(maxH, ch);
      return { ...c, gridW: w, gridH: h, x, y: 0, cw, ch };
    });

    // Add district labels (2 rows worth of height)
    const labelH = 2 * SPRITE_PX;
    const mapH = maxH + labelH + 2;

    // Render each column
    const W = totalW;
    const H = mapH;
    const imgData = new Array(W * H).fill('0');
    function setPx(x, y, ch) {
      if (x >= 0 && x < W && y >= 0 && y < H) imgData[y * W + x] = ch;
    }
    function drawSprite(sprite, dx, dy) {
      if (!sprite || !sprite.length) return;
      for (let row = 0; row < 16 && dy + row < H; row++) {
        const line = sprite[row];
        if (!line) continue;
        for (let col = 0; col < 16 && dx + col < W; col++) {
          const ch = line[col];
          if (ch && ch !== '0') setPx(dx + col, dy + row, ch);
        }
      }
    }

    colData.forEach(c => {
      // District label strip
      const label = c.district.label;
      for (let i = 0; i < label.length && i < 14; i++) {
        setPx(c.x + i, 0, 'f'); // gold label area
      }

      // Representations
      c.reps.forEach((r, idx) => {
        const gx = c.x + (idx % c.gridW) * SPRITE_PX;
        const gy = labelH + Math.floor(idx / c.gridW) * SPRITE_PX;
        drawSprite(r.sprite, gx, gy);
        // Store position on the rep object
        r._x = gx;
        r._y = gy;
        r._col = c;
      });
    });

    return { imgData, W, H, colData };
  }

  let mapData = buildMap();

  // ── render: nearest-neighbour scaled ────────────────────────────────
  function render() {
    const rect = wrap.getBoundingClientRect();
    const vw = rect.width;
    const vh = rect.height;

    // Calculate scale to fit the map comfortably, cap at 2x
    const fitX = vw / (mapData.W);
    const fitY = vh / (mapData.H);
    scale = Math.min(fitX, fitY, 2.0);
    if (scale < 0.25) scale = 0.25;

    canvas.width = Math.ceil(mapData.W * scale);
    canvas.height = Math.ceil(mapData.H * scale);
    canvas.style.width = canvas.width + 'px';
    canvas.style.height = canvas.height + 'px';

    const ctx = canvas.getContext('2d');
    const img = ctx.createImageData(canvas.width, canvas.height);
    const d = img.data;

    for (let y = 0; y < canvas.height; y++) {
      const srcY = Math.floor(y / scale);
      for (let x = 0; x < canvas.width; x++) {
        const srcX = Math.floor(x / scale);
        const ch = mapData.imgData[srcY * mapData.W + srcX] || '0';
        const col = palette[ch] || '#000000';
        const idx = (y * canvas.width + x) * 4;
        d[idx] = parseInt(col.slice(1,3), 16);
        d[idx+1] = parseInt(col.slice(3,5), 16);
        d[idx+2] = parseInt(col.slice(5,7), 16);
        d[idx+3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);

    // Update legend
    legend.innerHTML = '<b>Districts</b>' +
      districts.map(d => '<span><span class="legend-b" style="background:'+(palette['f']||'#f0c040')+'"></span>' + d.label + '</span>').join("");

    // Centre the canvas initially if pan hasn't been set
    if (panX === 0 && panY === 0) {
      panX = Math.max(0, (vw - canvas.width) / 2);
      panY = Math.max(0, (vh - canvas.height) / 2);
    }
    canvas.style.marginLeft = panX + 'px';
    canvas.style.marginTop = panY + 'px';
  }

  // ── hit testing ────────────────────────────────────────────────────
  function hitTest(cx, cy) {
    // cx, cy are client coordinates relative to wrap
    const rect = wrap.getBoundingClientRect();
    const mx = (cx - rect.left - panX) / scale;
    const my = (cy - rect.top - panY) / scale;

    for (const r of world.representations) {
      if (r._x !== undefined) {
        const rx = r._x;
        const ry = r._y;
        if (mx >= rx && mx < rx + SPRITE_PX && my >= ry && my < ry + SPRITE_PX) {
          return r;
        }
      }
    }
    return null;
  }

  // ── panel ──────────────────────────────────────────────────────────
  function openPanel(r) {
    selected = r;
    const kindIcon = { building:'🏢', item:'💎', block:'🧱', character:'🧑' };
    const icon = kindIcon[r.kind] || '📦';
    const what = r.module || r.team || r.account || r.asset || '—';
    const whatLabel = r.module ? 'Module' : r.team ? 'Team' : r.account ? 'Account' : 'Asset';

    panel.innerHTML = '<button class="close" onclick="document.getElementById(\'panel\').classList.remove(\'open\')">✕</button>' +
      '<h2>' + icon + ' ' + r.n + '</h2>' +
      '<div class="sub">' + r.kind + ' — ' + whatLabel + ': ' + what + '</div>' +
      '<span class="status status-' + r.status + '">' + r.status + '</span>' +
      '<div style="margin:10px 0 0"><strong>District:</strong> ' + r.place + '</div>';

    if (r.recipes && r.recipes.length) {
      panel.innerHTML += '<div style="margin:10px 0 6px;font-size:13px;color:var(--muted)">Recipes</div>';
      r.recipes.forEach(rec => {
        panel.innerHTML += '<div class="recipe"><h3>⚡ ' + rec.action + '</h3>' +
          (rec.inputs && rec.inputs.length ? '<p>Inputs: ' + rec.inputs.join(', ') + '</p>' : "") +
          (rec.outputs && rec.outputs.length ? '<p>Outputs: ' + rec.outputs.join(', ') + '</p>' : "") +
          '</div>';
      });
    } else {
      panel.innerHTML += '<p style="color:var(--muted);font-size:13px;margin-top:8px">No recipes declared</p>';
    }

    panel.classList.add('open');
  }

  // ── search ─────────────────────────────────────────────────────────
  search.addEventListener('input', function() {
    const q = this.value.toLowerCase().trim();
    if (!q) return;
    const matches = world.representations.filter(r =>
      r.n.toLowerCase().includes(q) ||
      r.place.toLowerCase().includes(q) ||
      r.kind.toLowerCase().includes(q) ||
      (r.module && r.module.toLowerCase().includes(q)) ||
      (r.team && r.team.toLowerCase().includes(q))
    );
    if (matches.length === 1) {
      openPanel(matches[0]);
    } else if (matches.length > 1) {
      // Show first match
      openPanel(matches[0]);
    }
  });

  // ── mouse/touch events ─────────────────────────────────────────────
  wrap.addEventListener('mousedown', function(e) {
    dragging = true;
    dragStartX = e.clientX;
    dragStartY = e.clientY;
    panStartX = panX;
    panStartY = panY;
  });
  window.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    const dx = e.clientX - dragStartX;
    const dy = e.clientY - dragStartY;
    panX = panStartX + dx;
    panY = panStartY + dy;
    canvas.style.marginLeft = panX + 'px';
    canvas.style.marginTop = panY + 'px';
  });
  window.addEventListener('mouseup', function(e) {
    if (!dragging) return;
    dragging = false;
    const dx = Math.abs(e.clientX - dragStartX);
    const dy = Math.abs(e.clientY - dragStartY);
    if (dx < 5 && dy < 5) {
      const hit = hitTest(e.clientX, e.clientY);
      if (hit) openPanel(hit);
    }
  });

  // Touch events
  let touchStartX, touchStartY, touchPanX, touchPanY, touching = false;
  wrap.addEventListener('touchstart', function(e) {
    if (e.touches.length === 1) {
      touching = true;
      touchStartX = e.touches[0].clientX;
      touchStartY = e.touches[0].clientY;
      touchPanX = panX;
      touchPanY = panY;
    }
  }, { passive: true });
  wrap.addEventListener('touchmove', function(e) {
    if (e.touches.length === 1 && touching) {
      panX = touchPanX + (e.touches[0].clientX - touchStartX);
      panY = touchPanY + (e.touches[0].clientY - touchStartY);
      canvas.style.marginLeft = panX + 'px';
      canvas.style.marginTop = panY + 'px';
    }
  }, { passive: true });
  wrap.addEventListener('touchend', function(e) {
    if (touching) {
      touching = false;
      const dx = Math.abs(e.changedTouches[0].clientX - touchStartX);
      const dy = Math.abs(e.changedTouches[0].clientY - touchStartY);
      if (dx < 8 && dy < 8) {
        const hit = hitTest(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
        if (hit) openPanel(hit);
      }
    }
  }, { passive: true });

  // ── runtime state (__twinState) ────────────────────────────────────
  if (window.__twinState) {
    const state = window.__twinState;
    if (state.agents) {
      Object.keys(state.agents).forEach(name => {
        const a = state.agents[name];
        // Update agent info on the world - displayed in the search bar area
        const info = document.createElement('div');
        info.style.cssText = 'position:absolute;bottom:8px;left:8px;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font-size:11px;z-index:5;';
        info.innerHTML = '<b>' + name + '</b>' +
          (a.lastMessage ? '<br>' + a.lastMessage : "") +
          (a.spendUsd != null ? '<br>$' + a.spendUsd.toFixed(2) + ' spent' : "");
        wrap.appendChild(info);
      });
    }
  }

  // ── init ───────────────────────────────────────────────────────────
  render();
  window.addEventListener('resize', render);

// ── deep-link support ──────────────────────────────────────────────
  // ?open=<name> opens that representation's panel on load.
  (function() {
    const params = new URLSearchParams(window.location.search);
    const openName = params.get('open');
    if (openName && repByName[openName]) {
      openPanel(repByName[openName]);
    }
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
    kindMap = { building = "Kind.building"; item = "Kind.item"; block = "Kind.block"; character = "Kind.character"; };
  in
  "  { name := ${q r.n}, kind := ${kindMap.${r.kind}}, of := { mod := ${ofModule}, account := ${ofAccount}, team := ${ofTeam}, asset := ${ofAsset} }, sprite := ${spriteStr}, place := ${q r.place}, recipes := [${
    lib.concatMapStringsSep ", " (
      rc: "  { action := ${q rc.action}, inputs := [${lib.concatMapStringsSep ", " (builtins.map q rc.inputs)}], outputs := [${lib.concatMapStringsSep ", " (builtins.map q rc.outputs)}] }"
    ) r.recipes
  }], status := ${q r.status} }"
) reps}
]

/-- The districts, rendered by the same. -/
def districts : List (String × District) := [
${lib.concatMapStringsSep ",\n" (
  d: "  (${q d.name}, { label := ${q d.label}, order := ${toString d.order} })"
) sortedDistricts}
]

/-- The governance action names that exist. -/
def governanceActions : List String := [
${lib.concatMapStringsSep ",\n" (
  a: "  ${q a}"
) (lib.concatLists (
  lib.mapAttrsToList (
    provider: as:
    lib.mapAttrsToList (
      name: _: "${provider}:${name}"
    ) as
  ) config.governance.actions
))}
]

/-- The perf-target module names. -/
def perfModules : List String := [
${lib.concatMapStringsSep ",\n" (
  m: "  ${q m}"
) (lib.unique (map (t: t.module) (lib.attrValues config.perf.targets)))}
]

/-- The agent names. -/
def agents : List String := [
${lib.concatMapStringsSep ",\n" (
  n: "  ${q n}"
) (lib.attrNames config.governance.agents)}
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

      checks.twin-view = pkgs.runCommand "twin-view"
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