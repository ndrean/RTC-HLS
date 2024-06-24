import addPlayer from "./addPlayer.js";
import joinChannel from "./signalingChannel.js";

function compare(x, y) {
  return BigInt(x) < BigInt(y);
}

const webRTC = {
  // global variables
  pcs: {},
  pc: null,
  pc_curr: null,
  channel: null,
  localStream: null,

  destroyed() {
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
    delete window.pcs;
    console.log("destroyed");
  },

  async mounted() {
    if (!window.navigator.mediaDevices) {
      alert("WebRTC is not supported in your browser");
      return;
    }

    const configuration = {
      iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
    };
    const mediaConstraints = {
      video: {
        facingMode: "user",
        frameRate: { ideal: 15 },
        width: { ideal: 320 },
        height: { ideal: 160 },
      },
      audio: true,
    };

    let rtc = this,
      iceCandidatesQueue = [];

    const userId = document.querySelector("#room-view").dataset.userId;
    const roomId = window.location.pathname.slice(1).split("/").pop();
    const module = document.querySelector("#room-view").dataset.module;

    async function handleOffer({ sdp, from, to }) {
      if (to !== userId) return;

      const pc = rtc.pcs[from];
      await pc.setRemoteDescription(sdp);
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      rtc.channel.push("answer", {
        sdp: pc.localDescription,
        type: "answer",
        from: to,
        to: from,
      });
      console.log("--> ", to, " sends Answer to", from);
    }

    async function handleAnswer({ from, to, sdp }) {
      if (to !== userId) return;
      const pc = rtc.pcs[from];

      await pc.setRemoteDescription(sdp);
      consumeIceCandidates(to);
      console.log("-->", to, " handled Answer from ", from);
    }

    async function handleCandidate({ candidate, from, to }) {
      if (to !== userId || !candidate) return;

      const pc = rtc.pcs[from];
      if (pc) {
        await pc.addIceCandidate(candidate);
        // console.log("--> Added ICE candidate from", from);
      } else {
        iceCandidatesQueue.push({ candidate, from });
        console.log("--> Queued ICE candidate from", from);
      }

      // console.log("--> Received ICE candidate");
    }

    function createConnection({ user, peer }, stream) {
      const pc = new RTCPeerConnection(configuration);
      stream.getTracks().forEach((track) => pc.addTrack(track, stream));

      pc.onicecandidate = (event) => {
        if (event.candidate) {
          rtc.channel.push("ice", {
            candidate: event.candidate,
            type: "ice",
            from: user,
            to: peer,
          });
        }
      };

      pc.ontrack = ({ streams }) => {
        addPlayer(streams[0], "v-" + peer);
      };

      pc.onnegotiationneeded = async () => {
        // !!! only one of the 2 peers should create the offer !!!
        if (!compare(user, peer)) return;

        console.log("-->", user, " creates Offer for ", peer);
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        rtc.channel.push("offer", {
          sdp: pc.localDescription,
          type: "offer",
          from: user,
          to: peer,
        });
      };

      pc.onconnectionstatechange = () => {
        const state = pc.connectionState;
        switch (state) {
          case "connected":
            console.log("~~> Connection state: ", state, { user, peer });
            const spin = document.querySelector("#spinner");
            if (spin) {
              spin.className = "hidden";
            }
            break;
          case "disconnected":
          case "failed":
          case "closed":
            console.log("~~> Connection state: ", state, { user, peer });
            delete rtc.pcs[peer];
            rtc.destroyed();
            break;
          default:
            console.log("~~> Connection state: ", state, { user, peer });
            break;
        }
      };

      rtc.pcs[peer] = pc;
      window.pcs = rtc.pcs;

      console.log("create Connection", { user, peer });

      return pc;
    }

    const channelOnlHandlers = {
      offer: handleOffer,
      answer: handleAnswer,
      ice: handleCandidate,
      ping: ({ from, to }) => {
        if (to !== userId) return;

        const peers = { user: userId, peer: from };
        console.log("wake up", peers);
        rtc.pc = createConnection(peers, rtc.localStream);
      },
      new: ({ from, to }) => {
        const peers = { user: userId, peer: from };

        if (from !== userId && to === undefined) {
          rtc.channel.push("ping", { from: userId, to: from });
          console.log("new peer", peers);
          rtc.pc = createConnection(peers, rtc.localStream);
        }
      },
    };

    this.localStream = await navigator.mediaDevices.getUserMedia(
      mediaConstraints
    );
    addPlayer(this.localStream, userId, "local");

    // the channel.on callbacks are defined above. They need localStream above. Respect the order.
    this.channel = await joinChannel(
      { roomId, userId, module },
      channelOnlHandlers
    );

    function consumeIceCandidates(from) {
      while (iceCandidatesQueue.length > 0) {
        console.log("ICE: consume queued from ", from);
        iceCandidatesQueue = iceCandidatesQueue.filter(async (item) => {
          if (item.from === from) {
            await rtc.pcs[from].addIceCandidate(item.candidate);
            return false;
          }
          return true;
        });
      }
    }

    // brings in the drag & drop video module to move the local video player
    // the 'touch' event is not supported
    await import("./dndVideo.js");
  },
};

export default webRTC;
