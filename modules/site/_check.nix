# Shared page-check renderer for the site and twin modules.
#
#   pageCheck { pkgs, htmlPath, name ? "page-check", viewports ? null,
#               additionalUrls ? [] }
#
# Renders an HTML page in the pinned Chromium at each viewport, keeping
# screenshots and the rendered DOM dump with JS-based assertions.
#
# Eval-time (pure Nix) assertions: none — every text analysis of the HTML
# (CSS custom properties, unbroken-code overflow, inline widths, overflow-x)
# happens in the derivation with python3 over the built index.html. Nix only
# passes file paths and the token-pair JSON.
#
# Runtime checks (in the derivation):
#   - WCAG contrast >= 4.5:1 for every :root CSS custom property pair
#     in both light and dark mode, computed from the hex values declared
#     in the :root blocks of the page's <style>
#   - No <pre> or block <code> without overflow-x: auto
#   - No inline width: exceeds 390px (outside meta viewport)
#   - No horizontal scroll at current viewport (DOM JS)
#   - Every link and button >= 44x44 CSS px (DOM JS)
#
# Parameters:
#   htmlPath        - path to the HTML file (derivation or store path)
#   name            - derivation name
#   viewports       - list of { width, height, label }; defaults to phone+desktop
#   additionalUrls  - list of { url, label, assertions: [{ pattern, msg }] }
#                     each additional URL is loaded directly in Chromium and the
#                     DOM grepped for each pattern
{
  pkgs,
  htmlPath,
  name ? "page-check",
  viewports ? null,
  additionalUrls ? [ ],
}:

let
  inherit (builtins) toString;
  inherit (pkgs) lib;

  # -- Default viewports --------------------------------------------------
  defaultViewports = [
    {
      width = 390;
      height = 844;
      label = "phone";
    }
    {
      width = 1280;
      height = 800;
      label = "desktop";
    }
  ];
  vps = if viewports == null then defaultViewports else viewports;

  # -- Token pair metadata ------------------------------------------------
  # Define which (fg, bg) token pairs must be checked in each colour mode.
  # This is pure Nix metadata — Python reads it as JSON and resolves the
  # actual hex values from the CSS :root blocks.
  tokenPairNames = [
    {
      fg = "fg";
      bg = "bg";
    }
    {
      fg = "accent";
      bg = "bg";
    }
    {
      fg = "muted";
      bg = "bg";
    }
    {
      fg = "fg";
      bg = "card";
    }
    {
      fg = "muted";
      bg = "card";
    }
    {
      fg = "accent";
      bg = "card";
    }
    {
      fg = "gap";
      bg = "bg";
    }
    {
      fg = "ok";
      bg = "bg";
    }
    {
      fg = "#ffffff";
      bg = "ci-queued";
    }
    {
      fg = "#ffffff";
      bg = "ci-inprogress";
    }
    {
      fg = "#ffffff";
      bg = "ci-success";
    }
    {
      fg = "#ffffff";
      bg = "ci-failure";
    }
    {
      fg = "#ffffff";
      bg = "ci-cancelled";
    }
    {
      fg = "muted";
      bg = "ci-skip";
    }
  ];

  # Produce the combined JSON: each pair duplicated for light and dark mode
  tokenPairsJson = builtins.toJSON (
    lib.concatMap
      (
        mode:
        map (p: {
          inherit mode;
          inherit (p) fg;
          inherit (p) bg;
        }) tokenPairNames
      )
      [
        "light"
        "dark"
      ]
  );

  # -- Runtime DOM-assertion JavaScript lives in its own file so no quoting
  # conflicts between Nix strings, shell escaping and JavaScript ever arise.
  # Nix only passes the file path; the shell concatenates it into the HTML.
  checkJs = ./_check.js;

  # -- Build the screenshot command for all viewports ----------------------
  screenshotCmds = lib.concatStringsSep "\n" (
    map (vp: ''
      echo "  -> ${lib.escapeShellArg vp.label} (${toString vp.width}x${toString vp.height})"
      chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
        --window-size=${toString vp.width},${toString vp.height} \
        --screenshot=$out/screenshot-${lib.escapeShellArg vp.label}.png \
        file://${htmlPath} 2>/dev/null
      test -s $out/screenshot-${lib.escapeShellArg vp.label}.png
    '') vps
  );

  # -- DOM dump commands --------------------------------------------------
  domDumpCmds = lib.concatStringsSep "\n" (
    map (vp: ''
      echo "  -> DOM dump at ${lib.escapeShellArg vp.label}"
      { sed '/<\/body>/,$d' ${htmlPath}; echo "<script>"; cat ${checkJs}; echo "</script></body></html>"; } \
        > $TMPDIR/check-${lib.escapeShellArg vp.label}.html

      chromium --headless=new --no-sandbox --disable-gpu \
        --window-size=${toString vp.width},${toString vp.height} \
        --run-all-compositor-stages-before-draw \
        --dump-dom file://$TMPDIR/check-${lib.escapeShellArg vp.label}.html 2>/dev/null \
        > $out/dom-${lib.escapeShellArg vp.label}.txt

      grep -E '^(PASS|FAIL) ' $out/dom-${lib.escapeShellArg vp.label}.txt > $out/results-${lib.escapeShellArg vp.label}.txt || true

      if grep -q '^FAIL ' $out/results-${lib.escapeShellArg vp.label}.txt; then
        echo "FAILURES at ${lib.escapeShellArg vp.label}:" >&2
        grep '^FAIL ' $out/results-${lib.escapeShellArg vp.label}.txt >&2
        exit 1
      fi
      echo "  All assertions passed at ${lib.escapeShellArg vp.label}"
    '') vps
  );

  # -- Additional URLs commands ------------------------------------------
  additionalUrlCmds = lib.concatStringsSep "\n" (
    map (
      au:
      let
        urlLabel = au.label or "extra";
        assertions = au.assertions or [ ];
      in
      ''
        echo "  -> Additional URL: ${lib.escapeShellArg urlLabel}"
        chromium --headless=new --no-sandbox --disable-gpu \
          --window-size=390,844 \
          --run-all-compositor-stages-before-draw \
          --dump-dom ${lib.escapeShellArg au.url} 2>/dev/null \
          > $out/dom-${lib.escapeShellArg urlLabel}.txt

        ${lib.concatStringsSep "\n" (
          map (a: ''
            if ! grep -q ${lib.escapeShellArg a.pattern} $out/dom-${lib.escapeShellArg urlLabel}.txt; then
              echo "FAIL: ${lib.escapeShellArg urlLabel}: ${lib.escapeShellArg a.msg}" >&2
              exit 1
            fi
            echo "  PASS: ${lib.escapeShellArg urlLabel}: ${lib.escapeShellArg a.msg}"
          '') assertions
        )}
      ''
    ) additionalUrls
  );

  # Path to the Python analysis script — lives in its own file so no
  # quoting conflicts between Nix indented strings and Python string
  # literals ever arise.  Nix passes values only through command-line
  # arguments (the HTML path) and the tokenPairsJson file (passed via
  # passAsFile / $tokenPairsJsonPath).
  checkScript = ./_check.py;

in

pkgs.runCommand name
  {
    nativeBuildInputs = [
      pkgs.chromium
      pkgs.python3
    ];
    inherit tokenPairsJson;
    passAsFile = [ "tokenPairsJson" ];
  }
  ''
    export HOME=$TMPDIR
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }}

    mkdir $out

    # -- HTML/CSS text analysis (Python) --------------------------------
    # Reads the built index.html to extract :root custom properties,
    # check overflow-x on <pre> tags, check inline widths > 390px,
    # and compute WCAG contrast ratios.
    echo "--- HTML/CSS analysis ---"
    python3 ${checkScript} ${htmlPath} $tokenPairsJsonPath

    # -- Screenshots ----------------------------------------------------
    echo "--- Screenshots ---"
    ${screenshotCmds}
    echo "  All screenshots captured."

    # -- DOM assertions --------------------------------------------------
    echo "--- Runtime DOM assertions ---"
    ${domDumpCmds}

    # Additional URL checks
    ${lib.optionalString (builtins.length additionalUrls > 0) ''
      echo "--- Additional URL checks ---"
      ${additionalUrlCmds}
    ''}
    echo "  All DOM assertions passed."

    # -- Copy source HTML for inspection ---------------------------------
    cp ${htmlPath} $out/index.html
    echo "Done."
  ''
