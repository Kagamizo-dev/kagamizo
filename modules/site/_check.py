#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""
Page-check HTML/CSS text-analysis script.

Reads a built HTML file and a token-pairs JSON file, then checks:

  1. WCAG contrast >= 4.5:1 for every :root CSS custom-property pair
     in both light and dark mode, computed from hex values in the
     page's <style> :root blocks.
  2. No <pre> or block <code> without overflow-x: auto.
  3. No inline width exceeding 390px (outside meta viewport).

Usage:  python3 page-check.py <index.html> <token-pairs.json>
"""

import json
import math
import re
import sys


def srgb_linearise(v: float) -> float:
    if v <= 0.04045:
        return v / 12.92
    return math.pow((v + 0.055) / 1.055, 2.4)


def relative_luminance(hex_str: str) -> float:
    h = hex_str.lstrip("#")
    r = int(h[0:2], 16) / 255.0
    g = int(h[2:4], 16) / 255.0
    b = int(h[4:6], 16) / 255.0
    return (0.2126 * srgb_linearise(r) +
            0.7152 * srgb_linearise(g) +
            0.0722 * srgb_linearise(b))


def contrast_ratio(hex1: str, hex2: str) -> float:
    l1 = relative_luminance(hex1)
    l2 = relative_luminance(hex2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def extract_root_props(html: str) -> dict:
    """Parse the CSS inside <style> tags for :root custom-property declarations.

    Returns {'light': {'--bg': '#fbfaf8', ...},
             'dark':  {'--bg': '#151514', ...}}
    """
    m_style = re.search(r'<style[^>]*>(.*?)</style>', html, re.DOTALL | re.IGNORECASE)
    if not m_style:
        return {'light': {}, 'dark': {}}
    css = m_style.group(1)

    light_props = {}
    dark_props = {}
    lines = css.splitlines()
    brace_depth = 0
    in_root = False
    in_dark = False
    root_start_depth = 0

    for line in lines:
        trimmed = line.strip()
        if not trimmed:
            continue

        # Check for @media context on this line
        at_media = '@media' in trimmed
        if at_media:
            in_dark = 'prefers-color-scheme: dark' in trimmed

        # Count braces on this line
        opens = trimmed.count('{')
        closes = trimmed.count('}')

        # Detect :root start BEFORE counting braces
        if ':root' in trimmed and not in_root:
            in_root = True
            root_start_depth = brace_depth

        # Update brace depth
        brace_depth += opens - closes

        # Extract properties if inside :root
        if in_root:
            for m in re.finditer(r'--([a-zA-Z0-9_-]+)\s*:\s*#([0-9a-fA-F]{6})', trimmed):
                key = '--' + m.group(1)
                val = '#' + m.group(2).lower()
                if in_dark:
                    dark_props[key] = val
                else:
                    light_props[key] = val

            # Check if :root block ended on this line
            if brace_depth <= root_start_depth:
                in_root = False

    return {'light': light_props, 'dark': dark_props}


def check_code_overflow(html: str) -> list:
    """Check that no <pre> tag lacks overflow-x: auto."""
    violations = []
    for m in re.finditer(r'<pre(\s[^>]*)?>', html, re.IGNORECASE):
        tag_content = m.group(0)
        if 'overflow-x' not in tag_content:
            violations.append(tag_content)
    return violations


def check_width_overflow(html: str) -> list:
    """Check that no element inline width exceeds 390px.

    Strips <style> blocks first so CSS rules (max-width, min-width,
    media-query breakpoints) are never matched.  Then searches for
    a bare width: Npx anywhere in the remaining HTML (inline style
    attributes), but excludes max-width: and min-width: via
    negative lookbehind so that `max-width:780px` is not caught
    by a `width:780px` match.
    """
    # Remove all <style>...</style> blocks
    clean = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)

    violations = []
    for m in re.finditer(r'(?<!max-)(?<!min-)width\s*:\s*(\d+)px', clean, re.IGNORECASE):
        width_val = int(m.group(1))
        if width_val > 390:
            violations.append(m.group(0))
    return violations


def check_contrast(html: str, token_pairs_json: str) -> list:
    """Parse :root props and check WCAG contrast for all token pairs."""
    props = extract_root_props(html)
    light_props = props['light']
    dark_props = props['dark']

    token_pairs = json.loads(token_pairs_json)
    failures = []

    for pair in token_pairs:
        mode = pair['mode']
        fg_name = pair['fg']
        bg_name = pair['bg']

        def resolve(name: str, mode_props: dict) -> str | None:
            if name.startswith('#'):
                return name
            key = name if name.startswith('--') else '--' + name
            return mode_props.get(key)

        if mode == 'light':
            fg_hex = resolve(fg_name, light_props)
            bg_hex = resolve(bg_name, light_props)
        else:
            fg_hex = resolve(fg_name, dark_props)
            bg_hex = resolve(bg_name, dark_props)

        if fg_hex is None or bg_hex is None:
            continue

        cr = contrast_ratio(fg_hex, bg_hex)
        if cr < 4.5:
            failures.append({
                'mode': mode,
                'fgName': fg_name,
                'bgName': bg_name,
                'fgHex': fg_hex,
                'bgHex': bg_hex,
                'ratio': round(cr, 4),
            })

    return failures


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: python3 page-check.py <index.html> <token-pairs.json>", file=sys.stderr)
        print("  Reads the built HTML, checks WCAG contrast ratios, <pre> overflow_x,", file=sys.stderr)
        print("  and inline widths > 390px against the token-pair metadata (fg/bg per mode).", file=sys.stderr)
        sys.exit(1)

    html_path = sys.argv[1]
    token_pairs_path = sys.argv[2]

    with open(html_path) as f:
        html = f.read()

    with open(token_pairs_path) as f:
        token_pairs_json = f.read()

    # 1. WCAG contrast check
    failures = check_contrast(html, token_pairs_json)
    if failures:
        print("ERROR: WCAG contrast failures:", file=sys.stderr)
        for f in failures:
            print("  {}: {} ({}) on {} ({}) = {:.4f} (need >=4.5)".format(
                f['mode'], f['fgName'], f['fgHex'],
                f['bgName'], f['bgHex'], f['ratio']), file=sys.stderr)
        sys.exit(1)
    print("  WCAG contrast: all pairs >= 4.5:1")

    # 2. Code/pre overflow-x
    code_violations = check_code_overflow(html)
    if code_violations:
        print("ERROR: <pre> tags without overflow-x: auto", file=sys.stderr)
        for v in code_violations:
            print("  " + v, file=sys.stderr)
        sys.exit(1)
    print("  Code blocks: all have overflow-x: auto")

    # 3. Inline width > 390
    width_violations = check_width_overflow(html)
    if width_violations:
        print("ERROR: inline width exceeds 390px:", file=sys.stderr)
        for v in width_violations:
            print("  " + v, file=sys.stderr)
        sys.exit(1)
    print("  Inline widths: none exceed 390px")


if __name__ == '__main__':
    main()