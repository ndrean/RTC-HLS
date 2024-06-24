import roomSocket from "./roomSocket";

// make this function async to ensure the channel is joined before starting the WebRTC process
/**
 * Joins a channel for a given room and user.
 * @param {string} roomId - The ID of the room to join.
 * @param {string} userId - The ID of the user joining the room.
 * @param {Object} handlers - An object containing event handlers.
 * @returns {Promise<Channel>} - A promise that resolves to the joined channel.
 */
export default async function joinChannel(
  { roomId, userId, module },
  handlers
) {
  return new Promise((resolve) => {
    const channel = roomSocket.channel("room:" + roomId, { userId, module });

    channel
      .join()
      .receive("error", (resp) => {
        console.log("Unable to join", resp);
        window.location.href = "/";
      })
      .receive("ok", () => {
        console.log(`Joined successfully room:${roomId}`);
        setHandlers(channel, handlers);
        resolve(channel);
      });
  });
}

function setHandlers(channel, handlers) {
  for (let key in handlers) {
    channel.on(key, handlers[key]);
  }
}
