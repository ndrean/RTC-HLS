/**
 * Sets up a video player for a given ID with the given media stream.
 *
 * @param {string} eltId - The ID of the video element to set up.
 * @param {MediaStream} stream - The media stream to be played.
 * @returns {HTMLVideoElement} - The video element set up with the media stream.
 */
export default function setPlayer(eltId, stream, from = "") {
  const video = document.getElementById(eltId);

  if (!video) {
    console.error("video element not found");
    return;
  }

  console.warn("video: ", video.id);

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
  console.log(video);
  return video;
}
