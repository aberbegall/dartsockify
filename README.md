# dartsockify
A dart implementation of the websockify WebSocket-to-TCP bridge/proxy.

### credits
https://github.com/novnc/websockify

### how to use
`dart dartsockify.dart [--web web_dir] [--cert cert.pem [--key key.pem]] source_port target_addr:target_port`
> dart dartsockify.dart --web web_folder --cert cert.pem --key key.pem 5959 127.0.0.1:5900  

The api is very similar to the original websockify.js script

### missing websockify features 
* Session recorder
