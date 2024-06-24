import { Socket } from "phoenix";

export default new Socket("/room", {
  params: { user_token: window.userToken },
});
