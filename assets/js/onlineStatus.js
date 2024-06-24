const domEl = document.getElementById("online");

const status = {
  online: { src: "/images/online.svg", bg: "lavender", opacity: 0.8 },
  offline: { src: "/images/offline.svg", bg: "tomato" },
};

/**
 * Sets the online status of the given DOM element.
 * @param {HTMLElement} el - The DOM element to update.
 * @param {Object} param1 - The status configuration object.
 * @param {number} [param1.opacity=1] - The opacity to set.
 * @param {string} param1.bg - The background color to set.
 * @param {string} param1.src - The image source to set.
 */
const setOnline = (el, { opacity = 1, bg, src }) => {
  el.style.opacity = opacity;
  el.src = src;
  el.style.backgroundColor = bg;
};

/**
 * Sets up event listeners to update the online status when the connection status changes.
 */
const statusListener = () => {
  window.onoffline = () => setOnline(domEl, status.offline);
  window.ononline = () => setOnline(domEl, status.online);
};

/**
 * Renders the initial online status based on the navigator's online status.
 * @param {HTMLElement} from - The source DOM element.
 * @param {HTMLElement} to - The target DOM element to update.
 */
function firstRender(from, to) {
  if (from.getAttribute("id") === "online") {
    navigator.onLine
      ? setOnline(to, status.online)
      : setOnline(to, status.offline);
  }
}

export { statusListener, firstRender };
