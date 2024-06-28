export function init(ctx, html) {
  ctx.importCSS("main.css");
  ctx.root.innerHTML = html;

  const iceConf = {
    iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
  };

  console.log(ctx);

  function run() {
    console.log(ctx);
    window.navigator.mediaDevices
      .getUserMedia({ video: { width: 400, height: 400 }, audio: false })
      .then((stream) => {
        const videoIn = document.getElementById("videoIn"),
          send = true;

        document.getElementById("stop").onclick = () => {
          send = false;
          ctx.pushEvent("stop", {});
        };

        videoIn.srcObject = stream;

        const pc = new RTCPeerConnection(iceConf);
        conosle.log(pc);
        const tracks = stream.getTracks();
        tracks.forEach((track) => pc.addTrack(track, stream));

        pc.onicecandidate = (evt) => {
          if (evt.candidate) {
            console.log(evt.candidate);
            ctx.pushEvent("ice", { candidate: evt.candidate, type: "ice" });
          }
        };

        pc.ontrack = ({ streams }) => {
          console.log("--> Received remote track");
          const echo = document.querySelector("#echo");
          echo.srcObject = streams[0];
          echo.onloadeddata = echo.play();
        };

        pc.onnegotiationneeded = async () => {
          const offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          console.log("--> Offer created and sent");
          ctx.pushEvent("offer", { sdp: offer, type: "offer" });
        };

        pc.onconnectionstatechange = () => {
          console.log("~~> Connection state: ", pc.connectionState);
        };

        ctx.handleEvent("offer", async (msg) => {
          await pc.setRemoteDescription(msg.sdp);
          const answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          console.log("got Offer");
          ctx.pushEvent("answer", { sdp: pc.localDescription, type: "answer" });
        });

        ctx.handleEvent("ice", async ({ candidate }) => {
          if (candidate === null) return;
          await pc.addIceCandidate(candidate);
        });

        ctx.handleEvent("answer", async (msg) => {
          await pc.setRemoteDescription(msg.sdp);
          console.log("--> handled Answer");
        });
      });
  }
  run();
}
