import { Socket } from "phoenix";

export default new Socket("/stream", {
  params: { user_token: window.userToken },
});
