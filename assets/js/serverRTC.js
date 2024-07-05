import setPlayer from "./setPlayer.js";
import joinChannel from "./signalingChannel.js";

const serverRTC = {
  // global variables cleanup
  pc: null,
  channel: null,
  localStream: null,
  int: null,

  destroyed() {
    console.log("destroyed");
    if (this.int) clearInterval(this.int);
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
      this.localStream = null;
    }

    if (this.channel) {
      this.channel.leave().receive("ok", () => {
        console.log("left room, closing channel", this.channel.topic);
      });
      this.channel = null;
    }
    if (this.pc) {
      this.pc.close();
      this.pc = null;
    }
    delete window.pc;
  },

  async mounted() {
    console.log("serverRTC mounted");
    if (!window.navigator.mediaDevices) {
      alert("You may need a secured connection.");
      return;
    }

    const configuration = {
      iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
    };

    const mediaConstraints = {
      video: {
        facingMode: "user",
        frameRate: { ideal: 30 },
        width: { ideal: 600 },
        height: { ideal: 320 },
      },
      audio: true,
    };

    const userId = document.querySelector("#room-view").dataset.userId;
    const roomId = window.location.pathname.slice(1).split("/").pop();
    const module = document.querySelector("#room-view").dataset.module;

    let rtc = this,
      i = 0,
      timeInt = 2000;

    const channelOnlHandlers = {
      offer: async (msg) => {
        await rtc.pc.setRemoteDescription(msg.sdp);
        const answer = await rtc.pc.createAnswer();
        await rtc.pc.setLocalDescription(answer);

        rtc.channel.push("answer", {
          sdp: rtc.pc.localDescription,
          type: "answer",
          from: userId,
        });

        console.log(`--> Offer from ${msg.from} handled and Answer sent`);
      },

      answer: async (msg) => {
        console.log(msg.sdp);
        await rtc.pc.setRemoteDescription(msg.sdp);
        console.log("--> handled Answer from ", msg.from);
      },

      ice: async ({ from, candidate }) => {
        if (candidate === null) {
          return;
        }
        //   console.log("--> Added ICE candidate from", from);
        console.log(candidate);
        await rtc.pc.addIceCandidate(candidate);
      },
    };

    const stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    // to close the Media when the user leaves the room
    rtc.localStream = stream;
    setPlayer("ex-local", stream);

    // the channel.on callbacks are defined above. They need localStream above. Respect the order.
    this.channel = await joinChannel(
      { roomId, userId, module },
      channelOnlHandlers
    );

    this.pc = new RTCPeerConnection(configuration);

    // add the the window object for debugging purposes
    window.pc = this.pc;

    // let tracks = stream.getTracks();
    let tracks = stream.getTracks();
    tracks.forEach((track) => rtc.pc.addTrack(track, stream));

    this.pc.onicecandidate = (event) => {
      if (event.candidate) {
        rtc.channel.push("ice", {
          candidate: event.candidate.toJSON(),
          type: "ice",
          from: userId,
        });
      }
    };

    this.pc.ontrack = ({ streams }) => {
      // console.log(`--> Received remote track`);
      setPlayer("ex-remote", streams[0]);
    };

    this.pc.onnegotiationneeded = async () => {
      const offer = await rtc.pc.createOffer();
      await rtc.pc.setLocalDescription(offer);
      rtc.channel.push("offer", { sdp: offer, type: "offer", from: userId });
      console.log(`--> Offer created and sent`);
    };

    this.pc.onconnectionstatechange = listenConnectionState;

    function listenConnectionState() {
      const state = rtc.pc.connectionState;
      console.log("~~> Connection state: ", state);
      if (state === "connected") {
        rtc.int = setInterval(logPacketSizes, timeInt);
      }

      if (
        state === "disconnected" ||
        state === "failed" ||
        state === "closed"
      ) {
        rtc.destroyed();
      }
    }

    async function logPacketSizes() {
      try {
        const stats = await rtc.pc.getStats();
        stats.forEach((report) => {
          if (report.type === "outbound-rtp" && report.kind === "video") {
            let bytesChange = report.bytesSent - i;
            i = report.bytesSent;
            let kbps = Math.round((bytesChange * 8) / timeInt);

            document.querySelector("#stats").textContent =
              "Video transfer rate: " + kbps + " kbps";
          }
        });
      } catch (error) {
        console.error("Error getting stats:", error);
      }
    }
    // brings in the drag & drop video module to move the local video player
    // the 'touch' event is not supported
    await import("./dndVideo.js");
  },
};

export default serverRTC;
