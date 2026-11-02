// Shows the "Your session has ended" dialog (session_ended_dialog() in functions.R,
// hidden in the page) when the connection to the server ends: after an hour at the
// latest (Cloud Run's limit for one request), or when the device goes to sleep or
// loses its network. Nothing can resume the session, so the only way on is Reload.
// The page is never reloaded on its own: that would throw away what the user is
// reading, and the dialog is the explanation.
(function () {
  var unloading = false;

  // Closing or reloading the page also closes the connection: that is not a lost session
  window.addEventListener("beforeunload", function () { unloading = true; });
  window.addEventListener("pagehide", function () { unloading = true; });
  window.addEventListener("pageshow", function () { unloading = false; });

  document.addEventListener("DOMContentLoaded", function () {
    var box = document.getElementById("session-ended");
    if (!box) return;

    var button = box.querySelector("button");
    button.addEventListener("click", function () { window.location.reload(); });

    // Shiny fires this through jQuery, which a native addEventListener never sees
    $(document).on("shiny:disconnected", function () {
      if (unloading || !box.hidden) return;
      box.hidden = false;
      button.focus();
    });
  });
})();
