const myWs = {
  ws: null,
  connect: ({ userToken }) => {
    myWs.ws = new WebSocket(
      `ws://${window.location.host}/echo/websocket?user_token=${userToken}&vsn=2.0.0`
    );
  },
  push: (payload) => {
    if (myWs.ws.readyState === WebSocket.OPEN) {
      myWs.ws.send(payload);
    }
  },
};

export default {
  localStream: null,
  mediaRecorder: null,
  readableStream: null,
  isRecordingStopped: false,
  ws: null,

  async mounted() {
    this.ws = myWs.connect({ userToken: window.userToken });

    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        frameRate: { ideal: window.fps },
      },
      audio: false,
    });
    const video = document.querySelector("#ex-local");
    video.srcObject = stream;
    this.localStream = stream;

    this.pushEvent("start-evision", {});

    this.mediaRecorder = new MediaRecorder(stream);

    // if (this.mediaRecorder && !this.isRecordingStopped) {
    this.readableStream = createStreamer(this.mediaRecorder);
    this.mediaRecorder.start(1_000);
    // }

    function createStreamer(mediaRecorder) {
      const readableStream = new ReadableStream({
        start(controller) {
          mediaRecorder.ondataavailable = ({ data }) => {
            if (data.size > 0) {
              controller.enqueue(data);
              console.log(data);
              myWs.push(data);
            }
          };

          mediaRecorder.onstop = () => {
            if (controller) {
              controller.close();
            }
          };
        },
      });
    }
  },

  destroyed() {
    this.localStream.getTracks().forEach((track) => track.stop());
    this.localStream = null;
    this.isRecordingStopped = true;
    if (this.mediaRecorder) {
      this.mediaRecorder.stop();
      this.mediaRecorder = null;
    }
    if (this.readableStream && !this.readableStream.locked) {
      this.readableStream.cancel();
    }
    this.localStream = null;
    myWs.ws.close();
  },
};
