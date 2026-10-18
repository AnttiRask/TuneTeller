// Light/dark switch (see mode_toggle_button() in functions.R). The page starts
// in dark mode; a click flips Bootstrap's data-bs-theme on <html>. The icon is
// swapped by CSS, and the button's label names the mode a click switches to.
(function () {
  var root = document.documentElement;

  // Set straight away (this script is in the head) so the page never flashes light
  root.setAttribute("data-bs-theme", "dark");

  function isDark() {
    return root.getAttribute("data-bs-theme") === "dark";
  }

  function setLabel(button) {
    var label = button.getAttribute(isDark() ? "data-label-to-light" : "data-label-to-dark");
    button.setAttribute("aria-label", label);
    button.setAttribute("title", label);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var button = document.getElementById("mode-toggle");
    if (!button) return;

    setLabel(button);
    button.addEventListener("click", function () {
      root.setAttribute("data-bs-theme", isDark() ? "light" : "dark");
      setLabel(button);
    });
  });
})();
