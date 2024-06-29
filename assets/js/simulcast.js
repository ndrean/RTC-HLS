document.getElementById("start").onclick = async () => {
  await run();
};

async function run() {
  let stream = await navigator.mediaDevices.getUserMedia({
    video: true,
    audio: false,
  });

  /* sender */
  let sender = new RTCPeerConnection();
  sender.onicecandidate = (e) => receiver.addIceCandidate(e.candidate);
  sender.addTransceiver(stream.getVideoTracks()[0], {
    direction: "sendonly",
    streams: [stream],
    sendEncodings: [
      { rid: "h", maxBitrate: 1200 * 1024 },
      { rid: "m", maxBitrate: 600 * 1024, scaleResolutionDownBy: 2 },
      { rid: "l", maxBitrate: 300 * 1024, scaleResolutionDownBy: 4 },
    ],
  });

  /* receiver */
  let receiver = new RTCPeerConnection();
  receiver.onicecandidate = (e) => sender.addIceCandidate(e.candidate);
  receiver.ontrack = (e) =>
    (document.getElementById("video").srcObject = e.streams[0]);

  let offer = await sender.createOffer();
  await sender.setLocalDescription(offer);
  await receiver.setRemoteDescription(offer);

  let answer = await receiver.createAnswer();
  await receiver.setLocalDescription(answer);
  await sender.setRemoteDescription(answer);
}
