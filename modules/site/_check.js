(function() {
  var results = [];
  function pass(msg) { results.push("PASS " + msg); }
  function fail(msg) { results.push("FAIL " + msg); }

  var vw = window.innerWidth;
  var vh = window.innerHeight;
  pass("viewport " + vw + "x" + vh);

  // 1. No horizontal scroll
  var scrollW = document.documentElement.scrollWidth;
  if (scrollW <= vw) {
    pass("scrollWidth(" + scrollW + ") <= " + vw);
  } else {
    fail("scrollWidth(" + scrollW + ") > " + vw + " (horizontal overflow)");
  }

  // 2. Every link and button at least 44x44 CSS px
  var interactive = document.querySelectorAll("a, button, input[type=submit], input[type=button], [role=button]");
  var small = [];
  interactive.forEach(function(el) {
    var rect = el.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      if (Math.round(rect.width) < 44 || Math.round(rect.height) < 44) {
        var tag = el.tagName.toLowerCase();
        var id = el.id ? "#" + el.id : "";
        var cls = el.className && typeof el.className === "string" ? "." + el.className.split(" ")[0] : "";
        small.push(tag + id + cls + " " + Math.round(rect.width) + "x" + Math.round(rect.height) + "px");
      }
    }
  });
  if (small.length === 0) {
    pass("all " + interactive.length + " interactive elements >= 44x44px");
  } else {
    fail("elements below 44x44: " + small.join(", "));
  }

  // Write results into a dedicated element
  var pre = document.createElement("pre");
  pre.id = "page-check-results";
  pre.textContent = results.join("\n");
  pre.style.cssText = "all:initial;position:fixed;top:0;left:0;z-index:99999;background:#fff;color:#000;font:12px/1.4 monospace;padding:8px;border:2px solid #000;max-height:300px;overflow:auto;white-space:pre-wrap;";
  document.body.appendChild(pre);
})();