import 'dart:io';
import 'dart:async';

import 'package:args/args.dart';

ArgResults allArguments;

int source_port;
String target_host;
int target_port;

Future main(List<String> args) async {
  try {
    final parser = new ArgParser();

    ArgResults allArguments = parser.parse(args);
    List<String> arguments = allArguments.rest;

    source_port = int.parse(arguments[0]);
    target_host = arguments[1].split(':')[0];
    target_port = int.parse(arguments[1].split(':')[1]);

    print('WebSocket settings: ');
    print(
        "    - proxying from localhost:$source_port to $target_host:$target_port");

    if (allArguments['web']) {
      print("    - Web server active. Serving: " + allArguments['web']);
    }
  } catch (e) {
    print(
        'websockify.js [-w web_dir] [-c cert.pem [-k key.pem]] source_port target_addr:target_port');
    exit(2);
  }

  print("Running in unencrypted HTTP (ws://) mode");

  int sourcePort = 4981;
  var server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, sourcePort);
  } catch (e) {
    print("Couldn't bind to port $sourcePort: $e");
    exit(-1);
  }
  print('Listening on port $sourcePort for HTTP request ...');
  await for (HttpRequest request in server) {
    handleWebRequest(request);
  }
}

Future handleWebRequest(HttpRequest request) async {
  try {
    if (request.uri.path.startsWith('/status')) {
      print('Status request...');
      WebSocket client = await WebSocketTransformer.upgrade(request);
      client.add('{}');
      await client.close();
    } else {
      if (request.uri.path.startsWith('/websockify')) {
        request.response.headers.clear();
        request.response.headers.set('Sec-WebSocket-Protocol', 'binary');
        request.response.headers.set('Sec-WebSocket-Version', '13');
        print('Websokify request...');

        // Setup the web socket connection
        WebSocket client;

        if (WebSocketTransformer.isUpgradeRequest(request)) {
          client = await WebSocketTransformer.upgrade(request);
        }

        // Setup a new tcp socket connection
        int targetPort = 5900;
        Socket target = await Socket.connect('162.132.203.30', targetPort);

        var clientStream = client.listen(
            (data) => handleWebSocketData(data, target),
            onDone: () => handleWebSocketDone(target),
            onError: (error) => handleWebSocketError(error, target),
            cancelOnError: true);

        print('WebSocket connection...');
        print('Protocol: $client.protocol');

        var targetStream = target.listen(
            (data) => handleSocketData(data, target, client),
            onDone: () => handleSocketDone(client),
            onError: (error) => handleSocketError(error, target, client),
            cancelOnError: true);

        var targetHost = target.address.host;
        print('Socket connected to target: $targetHost:$targetPort');
      }
    }
  } catch (e) {
    print('Exception in handleWebRequest: $e');
  }
}

Future handleWebSocketData(dynamic data, Socket target) async {
  try {
    target.add(data);
  } catch (e) {
    print(e);
  }
}

Future handleWebSocketDone(Socket target) async {
  try {
    print('WebSocket client disconnected');
    await target.close();
    target.destroy();
  } catch (e) {
    print(e);
  }
}

Future handleWebSocketError(error, Socket target) async {
  try {
    print('WebSocket client error $error');
    await target.close();
    target.destroy();
  } catch (e) {
    print(e);
  }
}

Future handleSocketData(List<int> data, Socket target, WebSocket client) async {
  try {
    client.add(data);
  } catch (e) {
    print('Client closed, cleaning up target');
    await target.close();
    target.destroy();
  }
}

Future handleSocketDone(WebSocket client) async {
  try {
    print('Target disconnected');
    await client.close();
  } catch (e) {
    print(e);
  }
}

Future handleSocketError(error, Socket target, WebSocket client) async {
  try {
    print('Target connection error');
    print(error);
    await target.close();
    target.destroy();
    await client.close();
  } catch (e) {
    print(e);
  }
}
