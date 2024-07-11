document.addEventListener("DOMContentLoaded", async function () {
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  let video1 = document.getElementById("source"),
    video2 = document.getElementById("output"),
    spinner = document.getElementById("spinner"),
    fileProc = document.getElementById("file-proc"),
    stop = document.getElementById("stop"),
    isReady = false;

  let socket = new WebSocket(
    `ws://localhost:4000/socket?csrf_token=${csrfToken}`
  );

  let stream = await navigator.mediaDevices.getUserMedia({
    video: { width: 640, height: 480 },
    audio: false,
  });

  video1.srcObject = stream;
  spinner.style.visibility = "hidden";
  video2.style.visibility = "hidden";

  const options = { mimeType: "video/webm; codecs=vp8" };
  let mediaRecorder = new MediaRecorder(stream);

  mediaRecorder.ondataavailable = async ({ data }) => {
    if (!isReady) return;
    if (data.size > 0) {
      console.log(data.size);
      const buffer = await data.arrayBuffer();
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(buffer);
      }
    }
  };

  fileProc.onclick = () => {
    isReady = true;
    if (mediaRecorder.state == "inactive") mediaRecorder.start(1_000);
    spinner.style.visibility = "visible";
  };

  stop.onclick = () => {
    mediaRecorder.stop();
    socket.send("stop");
    socket.close();
  };

  const Hls = window.Hls;

  socket.onmessage = async ({ data }) => {
    if (!data == "playlist_ready") return;
    spinner.style.visibility = "hidden";
    video2.style.visibility = "visible";
    let hls = new Hls();

    if (Hls.isSupported()) {
      hls.loadSource("/hls/playlist.m3u8");
      hls.attachMedia(video2);
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        video2.play();
      });
      hls.on(Hls.Events.ERROR, (event, data) => {
        console.log(event, data);
      });
      // Safari can play this natively
    } else if (video2.canPlayType("application/vnd.apple.mpegurl")) {
      video2.src = "/output/playlist.m3u8";
      video2.addEventListener("loadedmetadata", () => {
        video2.play();
      });
    }
  };
});

/*
let mediaSource = new MediaSource(),
  queue = [],
  sourceBuffer,
  buffer;
mimeCodec = 'video/webm; codecs="vp8, opus"';
// mimeCodec = 'video/mp4; codecs="avc1.64001E, mp4a.40.2"';

if (!MediaSource.isTypeSupported(mimeCodec)) {
  alert("Unsupported MIME type or codec: ", mimeCodec);
  throw new Error("Unsupported MIME type or codec: " + mimeCodec);
}

video2.src = URL.createObjectURL(mediaSource);

mediaSource.addEventListener("sourceopen", ({ target }) => {
  mediaSource = target;
  sourceBuffer = mediaSource.addSourceBuffer(mimeCodec);
  console.log("Source buffer created successfully.");
  video2.play();
  sourceBuffer.addEventListener("updateend", () => {
    if (queue.length > 0) {
      sourceBuffer.appendBuffer(queue.shift());
    }
  });
});
const delay = async (ms) => new Promise((resolve) => setTimeout(resolve, ms));

socket.onmessage = async ({ data }) => {
  buffer = await data.arrayBuffer();
  if (sourceBuffer.updating || queue.length > 0) {
    console.log("enqueue");
    queue.push(buffer);
  } else {
    console.log(data);
    await delay(5_000);
    sourceBuffer.appendBuffer(buffer);
  }
};
*/
