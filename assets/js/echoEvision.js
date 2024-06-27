export default {
  async mounted() {
    await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: "user",
        frameRate: { ideal: window.fps },
        width: { ideal: 1900 },
        height: { ideal: 1500 },
      },
      audio: false,
    });

    this.pushEvent("start-evision", {});
  },
};
