/*
!!! Does not work with Firefox. 
- Safari ok: animation is smooth.
- Chrome can have problems to cancel the animation. Animation is not smooth
*/

export const faceApi = {
  intId: null,
  localStream: null,
  channel: null,
  mediaRecorder: null,
  requestId: null,
  videoCallbackId: null,
  video: null,

  async mounted() {
    // the source of the webcam
    this.video = document.getElementById("webcam");
      // the video where we render to draw the face detection
    const overlayed = document.getElementById("overlayed"),
      displaySize = { width: this.video.width, height: this.video.height },
      [faceapi, stream] = await Promise.all([
        import("@vladmandic/face-api"),
        navigator.mediaDevices.getUserMedia({ video: true }),
      ]),
      _this = this;

    await faceapi.nets.tinyFaceDetector.loadFromUri("/models/face-api");
    this.video.srcObject = stream;
    this.video.onloadeddata = this.video.play;
    // a reference to stop the video stream once the component is destroyed
    this.localStream = stream;

    let canvas = null, isRecordingStopped = false;

    this.video.onplay = async () => {
      canvas = faceapi.createCanvasFromMedia(this.video);
      faceapi.matchDimensions(canvas, displaySize);

      // await drawAnimationOnCanvas();
      this.videoCallbackId = await this.video.requestVideoFrameCallback(update)
      // capture the animation drawn in the canvas at 20 fps
      const canvasStream = canvas.captureStream(20);

      /*
      const canvasStream = canvas.captureStream(20);
      console.log(canvasStream);
      // reference to cancel the recording when the component is destroyed
      this.mediaRecorder = new MediaRecorder(canvasStream);
      console.log(this.mediaRecorder);

      // start recording chunks of 1s
      this.mediaRecorder.start(1000);
      // when the MediaRecorder has a chunk of data, we
      // give it to the MediaRecorder and HTTP request to the server

      this.mediaRecorder.ondataavailable = sendBlobToServer;
      // visualizing the animation in the second video
      overlayed.srcObject = canvasStream;

      */

      this.mediaRecorder = new MediaRecorder(canvasStream);
      

      if (this.mediaRecorder) {
        const readableStream = createStreamer(this.mediaRecorder);
        sendStreamToServer(readableStream);
        overlayed.srcObject = canvasStream;
        this.mediaRecorder.start(1_000);
      };

      }


    async function update(now, meta) {
      console.log("here");
      const context = canvas.getContext("2d");
      context.drawImage(_this.video, 0, 0, displaySize.width, displaySize.height);
      const detections = await faceapi.detectAllFaces(
        _this.video,
        new faceapi.TinyFaceDetectorOptions()
      );
      const resizedDetections = faceapi.resizeResults(detections, displaySize);
      faceapi.draw.drawDetections(canvas, resizedDetections);
      // you need to take a reference to cancel the animation when the component is destroyed
      // _this.requestId = requestAnimationFrame(drawAnimationOnCanvas);
      _this.videoCallbackId = _this.video.requestVideoFrameCallback(update)
    }
    
    async function drawAnimationOnCanvas() {
      const context = canvas.getContext("2d");
      context.drawImage(video, 0, 0, displaySize.width, displaySize.height);
      const detections = await faceapi.detectAllFaces(
        _this.video,
        new faceapi.TinyFaceDetectorOptions()
      );
      const resizedDetections = faceapi.resizeResults(detections, displaySize);
      faceapi.draw.drawDetections(canvas, resizedDetections);
      // you need to take a reference to cancel the animation when the component is destroyed
      _this.requestId = requestAnimationFrame(drawAnimationOnCanvas);
    }

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

    function createStreamer(mediaRecorder) {
      const readableStream = new ReadableStream({
        start(controller) {
          mediaRecorder.ondataavailable = ({ data }) => {
            if (data.size > 0) {
              console.log(data.size);
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
      console.log("STOPPED");
      isRecordingStopped = true;
      this.mediaRecorder.stop();
      // this.destroyed()
    });
  },

  destroyed() {
    console.log("destroyed");
    // if (this.intId) clearInterval(this.intId);
    if (this.requestId) cancelAnimationFrame(this.requestId);
    if (this.videoCallbackId) this.video.cancelVideoFrameCallback(this.videoCallbackId);
    this.requestId = null;

    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
    }
    if (this.mediaRecorder) this.mediaRecorder.stop();
  },
};
