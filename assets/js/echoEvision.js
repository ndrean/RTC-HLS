export default {
    async mounted() {
      
      const mediaConstraints = {
          video: {
            facingMode: "user",
            frameRate: { ideal: 30 },
            width: { ideal: 1900 },
            height: { ideal: 1500 },
          },
          audio: false,
        }
  
      await navigator.mediaDevices.getUserMedia(mediaConstraints);

      this.pushEvent("start-evision", {});
    },
  };