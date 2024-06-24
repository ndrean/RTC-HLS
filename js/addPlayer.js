/**
 * Sets up a video player for a given ID with the given media stream.
 *
 * @param {string} eltId - The ID of the video element to set up.
 * @param {MediaStream} stream - The media stream to be played.
 * @returns {HTMLVideoElement} - The video element set up with the media stream.
 */
export default function addPlayer(stream, from, eltId = "new") {
  let video;

  if (document.getElementById(from)) return;

  if (eltId == "local") {
    video = document.getElementById("local");
  } else {
    video = document.createElement("video");
    video.id = from;
    video.className = "w-full h-auto object-cover rounded-l max-h-60";

    const fig = document.createElement("figure");
    const figcap = document.createElement("figcaption");
    figcap.textContent = from;
    fig.appendChild(video);
    fig.appendChild(figcap);
    document.querySelector("#videos").appendChild(fig);
  }

  video.srcObject = stream;
  video.controls = false;
  video.muted = true;
  video.playsInline = true;

  video.onloadeddata = (e) => {
    try {
      video.play();
    } catch (e) {
      console.error(e);
    }
  };
}
