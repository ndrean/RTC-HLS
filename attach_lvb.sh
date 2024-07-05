#!bin/sh

# how to run a PHoenix app and a Livebook atatched to it

handle_interrupted() {
    # kill all the background processes started by this script
    pkiil -P $$
}

trap handle_interrupted INT

LIVEBOOK_TOKEN_ENABLED=false
LIVEBOOK_DEFAULT_RUNTIME="attached:my_app@127.0.0.1:secret" \
livebook server @new &
iex --name my_app@127.0.0.1 --cookie secret -S mix phx.server
 
 
    Enter fullscreen mode