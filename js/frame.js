import streamSocket from "./streamSocket";

const frame = {
  intId: null,
  localStream: null,
  intCam: null,
  video: null,
  camera: null,
  channel: null,

  destroyed() {
    clearInterval(this.intId);
    clearInterval(this.intCam);
    this.video = null;
    this.localStream.getTracks().forEach((track) => track.stop());
    this.localStream = null;
    if (this.channel) {
      this.channel.leave();
    }
    console.log("destroyed");
  },

  async mounted() {
    const userId = document.querySelector("#frame-js").dataset.userId,
      mediaConstraints = {
        video: {
          facingMode: "user",
          frameRate: { ideal: 30 },
          width: { ideal: 1900 },
          height: { ideal: 1500 },
        },
        audio: false,
      },
      _this = this;

    // setup channel
    this.channel = streamSocket.channel("stream:frame", { userId });
    this.channel
      .join()
      .receive("error", (resp) => {
        console.log("Unable to join", resp);
        // window.location.href = "/";
      })
      .receive("ok", () => {
        console.log(`Joined successfully stream:frame`);
      });

    this.video = document.querySelector("#webcam");
    const stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    this.video.srcObject = stream;
    this.localStream = stream;
    const fps = 2;
    this.intId = setInterval(captureFrame, 1000 / fps, this.video);

    // async function captureFrame(video) {
    async function captureFrame(video) {
      const t0 = performance.now();

      const canvas = document.createElement("canvas"),
        ctx = canvas.getContext("2d"),
        w = video.videoWidth,
        h = video.videoHeight,
        targetW = 244,
        targetH = 244 * (h / w);

      // Resize the image into the canvas to the target dimensions that match the model requirements
      ctx.drawImage(video, 0, 0, w, h, 0, 0, targetW, targetH);

      /* 
      Convert the canvas content to a Blob in the WEBP format.
      This is much lighter than a PNG, and lighter than JPEG.
      It is more efficient than toDataURL:
       - you don't convert the whole canvas to a base64 string which is CPU demanding 
       and increases the size of the data (+30%)
       - the conversion to blob and reading as ArrayBuffer is less memory intensive than converting to base64
       - you convert to base 64 a small piece of data
       - you don't need to compress the data
      */
      const { promise, resolve } = Promise.withResolvers();
      canvas.toBlob(resolve, "image/webp", 0.9);
      const blob = await promise;
      checkCapture(blob);
      const arrayBuffer = await blob.arrayBuffer();

      const encodedB64 = arrayBufferToB64(arrayBuffer);

      // LiveView -> needs "handle_event("frame", ...) in the LiveView
      // _this.pushEvent("frame", { data: encodedB64 });
      _this.channel.push("frame", encodedB64);

      document.querySelector("#stats").textContent = `Image: ${(
        encodedB64.length / 1024
      ).toFixed(1)} kB, browser process: ${(performance.now() - t0).toFixed(
        0
      )} ms`;
    }

    // convert the ArrayBuffer to a b64 encoded string by chunks (btoa limitation to 16k characters)
    function arrayBufferToB64(arrayBuffer) {
      const bytes = new Uint8Array(arrayBuffer);
      const chunkSize = 0x8000; // 32kB chunks
      const chunks = [];
      // convert chunks of Uint8Array to binary strings and encode them to base64
      for (let i = 0; i < bytes.byteLength; i += chunkSize) {
        const chunk = bytes.subarray(i, i + chunkSize);
        const binaryString = Array.from(chunk)
          .map((byte) => String.fromCharCode(byte))
          .join("");
        chunks.push(btoa(binaryString));
      }
      return chunks.join("");
    }
    // check the captured image in the browser
    function checkCapture(blob) {
      const imgURL = URL.createObjectURL(blob);
      const imgElement = document.querySelector("#check-frame");
      imgElement.src = imgURL;
      imgElement.onload = () => {
        URL.revokeObjectURL(imgURL);
      };
    }
  },
};

export default frame;
