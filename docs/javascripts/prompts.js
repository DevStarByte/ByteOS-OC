/*
  Prompts in shell examples look as ByteShell draws them: the user (root in
  red), @host, the directory, and > or #. The copy button leaves them out
  and copies only the commands, ready to paste into ByteOS.

    alice@byteos ~>     root@byteos ~#     alice@byteos ~/p/x [1]>
*/
(function () {
  var PROMPT = /^([A-Za-z_][\w-]*)@([\w-]+) (\S*?)( \[\d+\])?([#>]) /;

  // Replace characters [from, to) of `code` (offsets in its text) with node,
  // across the highlighter's spans.
  function replaceRange(code, from, to, node) {
    var walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
    var pos = 0, start = null, end = null, n;
    while ((n = walker.nextNode())) {
      var len = n.nodeValue.length;
      if (start === null && from < pos + len) start = { node: n, offset: from - pos };
      if (to <= pos + len) { end = { node: n, offset: to - pos }; break; }
      pos += len;
    }
    if (!start || !end) return;
    var range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    range.deleteContents();
    range.insertNode(node);
  }

  function span(cls, text) {
    var s = document.createElement("span");
    s.className = cls;
    s.textContent = text;
    return s;
  }

  function mark(code) {
    if (code.dataset.bxPrompts) return;
    code.dataset.bxPrompts = "1";
    var text = code.textContent;
    var found = [];
    var offset = 0;
    text.split("\n").forEach(function (line) {
      var m = PROMPT.exec(line);
      if (m) found.push({ at: offset, m: m });
      offset += line.length + 1;
    });
    // from the end, so earlier offsets stay right
    for (var i = found.length - 1; i >= 0; i--) {
      var m = found[i].m;
      var root = m[1] === "root";
      var p = span("bx-prompt gp", "");
      p.appendChild(span(root ? "r" : "u", m[1]));
      p.appendChild(span("h", "@" + m[2] + " "));
      p.appendChild(span(root ? "r" : "u", m[3]));
      if (m[4]) p.appendChild(span("r", m[4]));
      p.appendChild(span("s", m[5] + " "));
      replaceRange(code, found[i].at, found[i].at + m[0].length, p);
    }
    // the copy button copies the commands only (Material prefers
    // data-clipboard-text over reading the block)
    var button = code.parentElement && code.parentElement.querySelector(".md-clipboard");
    if (found.length && button) {
      var copy = code.cloneNode(true);
      copy.querySelectorAll(".bx-prompt").forEach(function (n) { n.remove(); });
      button.setAttribute("data-clipboard-text", copy.textContent.replace(/\s+$/, ""));
    }
  }

  function run() {
    document.querySelectorAll(".language-sh pre > code, .language-console pre > code, .language-text pre > code")
      .forEach(mark);
  }

  // Material's instant navigation swaps pages without reloading
  if (typeof document$ !== "undefined") document$.subscribe(run);
  else document.addEventListener("DOMContentLoaded", run);
})();
