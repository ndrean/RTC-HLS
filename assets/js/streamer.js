import streamSocket from "./streamSocket";

export const InputHls = {
  localStream: null,
  video: null,
  mediaStream: null,
  channel: null,
  readableStream: null,

  async mounted() {
    const mediaConstraints = {
        video: {
          facingMode: "user",
          frameRate: { ideal: 30 },
          width: { ideal: 1900 },
          height: { ideal: 1500 },
        },
        audio: false,
      },
      _this = this,
      userId = document.querySelector("#hls").dataset.userId;

    // setup channel
    // this.channel = streamSocket.channel("stream:hls", { userId });
    // this.channel
    //   .join()
    //   .receive("error", (resp) => console.log("Unable to join", resp))
    //   .receive("ok", () => console.log(`Joined successfully stream:hls`));

    this.video = document.getElementById("hls-in-video");
    const stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    this.video.srcObject = stream;
    this.localStream = stream;

    this.mediaRecorder = new MediaRecorder(stream);
    let isRecordingStopped = false;

    if (this.mediaRecorder) {
      this.readableStream = createStreamer(this.mediaRecorder);
      sendStreamToServer(this.readableStream);
      this.mediaRecorder.start(1_000);
    }

    function createStreamer(mediaRecorder) {
      let controllerRef;
      const readableStream = new ReadableStream({
        start(controller) {
          controllerRef = controller;
          mediaRecorder.ondataavailable = ({ data }) => {
            if (data.size > 0 && controllerRef) {
              console.log(data.size);
              controllerRef.enqueue(data);
            }
          };

          mediaRecorder.onstop = () => {
            if (controllerRef) {
              controllerRef.close()
              controllerRef = null
            }}
        },
      });

      return readableStream;
    }

    async function sendStreamToServer(stream) {
      const writableStream = new WritableStream({
        async write(chunk) {
          if (isRecordingStopped) return;
          // _this.channel.push("data", { chunk });
          const formData = new FormData();
          formData.append(
            "file",
            new File([chunk], "chunk.webm", { type: "video/webm" })
          );
          formData.append("type", "hls");
            const resp = await fetch("/api/live-upload", {
              method: "POST",
              body: formData,
            });
            const res = await resp.text();
            console.log(res);
          
        },
      });

      if (!stream.locked) {
        await stream.pipeTo(writableStream);
      }
    }

    this.handleEvent("stop", () => {
      console.log("STOPPED");
      isRecordingStopped = true;
      this.mediaRecorder.stop();
      // this.destroyed()
    });
    
    /* we need to push the data to the server as a b64 string
    so we need to convert the Blob to a b64 string
    We use a FileReader to convert the Blob to a b64 string
    with the readAsDataURL method
    */
    /*
    this.mediaStream.ondataavailable = ({ data }) => {
      const reader = new FileReader();
      reader.readAsDataURL(data);
      reader.onloadend = () => {
        this.channel.push("data", reader.result);
      };
    };
    */

  },

  destroyed() {
    console.log("destroyed");
    if (this.channel) {
      this.channel.leave();
    }
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
    }
    if (this.mediaRecorder) {
      this.mediaRecorder.stop();
      this.mediaRecorder = null;
    }
    if (this.readableStream && !this.readableStream.locked) {
      this.readableStream.cancel();
    }
    this.localStream = null;
    this.video = null;
  },
};

export const LiveHls = {
  hls: null,

  async mounted() {
    const _this = this,
      video = document.getElementById("hls-out-video");

    const play = async () => {
      if (video.canPlayType("application/vnd.apple.mpegurl")) {
        video.src = `/hls/stream.m3u8`;
        console.log("canplay");
        video.addEventListener("canplay", () => video.play());
      } else {
        console.log("hls.js needed");
        const { Hls } = await import("hls.js");
        const hls = new Hls();
        hls.loadSource(`/hls/stream.m3u8`);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, () => video.play());
        _this.hls = hls;
      }
    };
    document.getElementById("play-hls").onclick = play;
  },
  destroyed() {
    if (this.hls) {
      this.hls.detachMedia();
      this.hls.destroy();
      console.log("HLS destroyed");
    }
  },
};

export const LiveDash = {
  async mounted() {
    // "https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd"
    const video = document.getElementById("dash-out-video"),
      manifestUrl = video.dataset.manifestUrl;

    document.getElementById("play-dash").onclick = () => play();

    async function play() {
      const { MediaPlayer } = await import("dashjs");
      const player = MediaPlayer().create();
      player.initialize(video, manifestUrl, true);
    }
  },
};

export const InputDash = {
  localStream: null,
  video: null,
  mediaStream: null,

  async mounted() {
    const mediaConstraints = {
      video: {
        facingMode: "user",
        frameRate: { ideal: 30 },
        width: { ideal: 1900 },
        height: { ideal: 1500 },
      },
      audio: false,
    };

    this.handleEvent("stop", () => {
      this.destroyed();
      return;
    });

    this.video = document.getElementById("dash-in-video");
    const stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    this.video.srcObject = stream;
    this.localStream = stream;

    this.mediaStream = new MediaRecorder(stream, {
      videoBitsPerSecond: 3_000_000,
    });

    this.mediaStream.ondataavailable = ({ data }) => {
      console.log(data);
      const reader = new FileReader();
      reader.readAsDataURL(data);
      reader.onloadend = () => {
        this.pushEvent("live", { input: "dash", data: reader.result });
      };
    };
    this.mediaStream.start(1_000);
  },

  destroyed() {
    console.log("destroyed");
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
    }
    if (this.mediaStream) {
      this.mediaStream.stop();
    }
    this.localStream = null;
    this.video = null;
    this.mediaStream = null;
  },
};
