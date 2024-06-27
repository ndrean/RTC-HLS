// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar.cjs";
import { firstRender, statusListener } from "./onlineStatus";
import roomSocket from "./roomSocket";
import streamSocket from "./streamSocket";

import serverRTC from "./serverRTC";
import webRTC from "./webRTC";
import frame from "././frame";
import faceApi from "./faceApi";
import { LiveHls, InputHls } from "./streamer";
import echoEvision from "./echoEvision";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    rtc: serverRTC,
    web: webRTC,
    frame,
    LiveHls,
    InputHls,
    faceApi,
    echo_evision: echoEvision,
  },
  dom: { onBeforeElUpdated: firstRender },
});

// connects the sockets
liveSocket.connect();
roomSocket.connect();
streamSocket.connect();

// online status listener
statusListener();

// progress bar on live navigation and form submits. Code splitting test
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => {
  topbar.show(300);
});
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// window.addEventListener("phx:js-exec", ({ detail }) => {
//   const elt = document.querySelector(detail.to);
//   if (elt) {
//     liveSocket.execJS(elt, elt.getAttribute(detail.attr));
//   }
// });

window.liveSocket = liveSocket;
// liveSocket.enableDebug();
// liveview.disableDebug();
// window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
//   reloader.enableServerLogs();
// });
