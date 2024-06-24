const localVideo = document.getElementById("ex-local");
const remoteVideo = document.getElementById("ex-remote");

if (localVideo && remoteVideo) {
  console.log("d&d");
  localVideo.addEventListener("mousedown", (event) => {
    console.log("click");
    localVideo.classList.add("dragging");
    // Get initial positions
    let shiftX = event.clientX - localVideo.getBoundingClientRect().left;
    let shiftY = event.clientY - localVideo.getBoundingClientRect().top;

    // Function to move the element to new coordinates
    const moveAt = (pageX, pageY) => {
      let newX = pageX - shiftX;
      let newY = pageY - shiftY;

      // Boundary checks
      const remoteRect = remoteVideo.getBoundingClientRect();
      const localRect = localVideo.getBoundingClientRect();

      if (newX < remoteRect.left) newX = remoteRect.left;
      if (newY < remoteRect.top) newY = remoteRect.top;
      if (newX + localRect.width > remoteRect.right)
        newX = remoteRect.right - localRect.width;
      if (newY + localRect.height > remoteRect.bottom)
        newY = remoteRect.bottom - localRect.height;

      localVideo.style.left = newX - remoteRect.left + "px";
      localVideo.style.top = newY - remoteRect.top + "px";
    };

    // Move the video on mousemove
    const onMouseMove = (event) => {
      moveAt(event.pageX, event.pageY);
    };

    // Attach the mousemove event listener
    document.addEventListener("mousemove", onMouseMove);

    // Drop the element when mouse is released
    localVideo.onmouseup = () => {
      document.removeEventListener("mousemove", onMouseMove);
      localVideo.onmouseup = null;
    };

    // Prevent default drag action
    localVideo.ondragstart = () => {
      return false;
    };
    // Ensure the video element is positioned absolutely within the container
    localVideo.style.position = "absolute";
    localVideo.style.zIndex = 1000; // Ensure the video stays on top during dragging
  });

  // Ensure the video element is positioned absolutely within the container
  localVideo.style.position = "absolute";
}
