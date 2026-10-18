// The server tells the page when the "Get Recommendation" button should wait
// (see the cooldown observer in server.R): disable it and show the seconds left.
(function () {
  function register() {
    Shiny.addCustomMessageHandler("tt-cooldown", function (message) {
      var button = document.getElementById("go");
      if (!button) return;
      button.disabled = message.disabled;
      button.textContent = message.label;
    });
  }

  if (window.Shiny) {
    register();
  } else {
    document.addEventListener("DOMContentLoaded", register);
  }
})();
