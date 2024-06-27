/*
!!! Does not work with Firefox. 
*/

export default {
  localStream: null,
  mediaRecorder: null,
  videoCallbackId: null,
  video: null,

  async mounted() {
    // the source of the webcam
    this.video = document.getElementById("webcam");

    const displaySize = {
      width: this.video.width,
      height: this.video.height,
    };

    const [faceapi, stream] = await Promise.all([
        import("@vladmandic/face-api"),
        navigator.mediaDevices.getUserMedia({ video: true }),
      ]),
      _this = this;

    // await faceapi.nets.tinyFaceDetector.loadFromUri("/models/face-api");
    await faceapi.nets.ssdMobilenetv1.loadFromUri("/models/face-api");

    this.video.srcObject = stream;
    this.video.onloadeddata = this.video.play;

    // a reference to stop the video stream once the component is destroyed
    this.localStream = stream;

    let canvas = null,
      isRecordingStopped = false;

    this.video.onplay = async () => {
      canvas = faceapi.createCanvasFromMedia(this.video);
      faceapi.matchDimensions(canvas, displaySize);

      if ("requestVideoFrameCallback" in HTMLVideoElement.prototype) {
        // draw the animation at the video rate, not at the browser rate
        this.videoCallbackId = await this.video.requestVideoFrameCallback(
          drawAtVideoRate
        );
        console.log(this.videoCallbackId);
      } else {
        alert(
          "The 'face-api.js' and 'requestVideoFrame' is not supported with this browser"
        );
        this.destroyed();
        return;
      }

      // capture the animation drawn in the canvas at window.fps = 20 fps
      // since we draw in the canvas.
      const canvasStream = canvas.captureStream(Number(window.fps));
      this.mediaRecorder = new MediaRecorder(canvasStream);

      if (this.mediaRecorder) {
        const readableStream = createStreamer(this.mediaRecorder);
        sendStreamToServer(readableStream);
        this.mediaRecorder.start(1_000);

        // the video where we render to draw the face detection
        const overlayed = document.getElementById("overlayed");
        overlayed.srcObject = canvasStream;
      }
    };

    async function drawAtVideoRate() {
      const context = canvas.getContext("2d");
      context.drawImage(
        _this.video,
        0,
        0,
        displaySize.width,
        displaySize.height
      );
      const detections = await faceapi.detectAllFaces(
        _this.video,
        // new faceapi.TinyFaceDetectorOptions()
        new faceapi.SsdMobilenetv1Options()
      );

      const resizedDetections = faceapi.resizeResults(detections, displaySize);

      faceapi.draw.drawDetections(canvas, resizedDetections);
      //a reference to cancel the animation when the component is destroyed
      _this.videoCallbackId =
        _this.video.requestVideoFrameCallback(drawAtVideoRate);
    }

    function createStreamer(mediaRecorder) {
      const readableStream = new ReadableStream({
        start(controller) {
          mediaRecorder.ondataavailable = ({ data }) => {
            if (data.size > 0) {
              controller.enqueue(data);
            }
          };

          mediaRecorder.onstop = () => {
            controller.close();
          };
        },
      });

      return readableStream;
    }

    async function sendStreamToServer(stream) {
      const writableStream = new WritableStream({
        async write(chunk) {
          if (isRecordingStopped) return;
          console.log(chunk.size);
          const formData = new FormData();
          formData.append(
            "file",
            new File([chunk], "chunk.webm", { type: "video/webm" })
          );
          formData.append("type", "face");

          let resp = await fetch("/api/live-upload", {
            method: "POST",
            body: formData,
          });
          await resp.text();
        },
      });

      await stream.pipeTo(writableStream);
    }

    this.handleEvent("stop", () => {
      isRecordingStopped = true;
      this.destroyed();
    });
  },

  destroyed() {
    console.log("Destroyed");
    if (this.videoCallbackId)
      this.video.cancelVideoFrameCallback(this.videoCallbackId);
    this.videoCallbackId = null;

    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
    }
    if (this.mediaRecorder) {
      this.mediaRecorder.stop();
    }
  },
};

// async function sendBlobToServer({ data }) {
//   if (data.size > 0) {
//     console.log(data.size);
//     const file = new File([data], "chunk.webm", {
//       type: "video/webm",
//     });
//     const formData = new FormData();
//     formData.append("file", file);

//     return fetch("/api/face-upload", {
//       method: "POST",
//       body: formData,
//     });
//   }
// }
