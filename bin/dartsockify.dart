import 'dart:io';
import 'dart:async';

import 'package:args/args.dart';
import 'package:http_server/http_server.dart';

String targetHost;
int sourcePort;
int targetPort;

Future main(List<String> args) async {
  VirtualDirectory webDirectory;
  String webHost;
  String certPath;
  String keyPath;

  try {
    const String webOption = 'web';
    const String certOption = 'cert';
    const String keyOption = 'key';
    final ArgParser parser = new ArgParser()
      ..addOption(webOption, abbr: 'w')
      ..addOption(certOption, abbr: 'c')
      ..addOption(keyOption, abbr: 'k');

    ArgResults argOptions = parser.parse(args);
    List<String> arguments = argOptions.rest;

    sourcePort = int.parse(arguments[0]);
    targetHost = arguments[1].split(':')[0];
    targetPort = int.parse(arguments[1].split(':')[1]);
    webHost = argOptions[webOption];
    certPath = argOptions[certOption];
    keyPath = argOptions[keyOption];
  } catch (e) {
    print(
        'dartsockify.js [--web web_dir] [--cert cert.pem [--key key.pem]] source_port target_addr:target_port');
    exit(2);
  }

  print('WebSocket settings: ');
  print(
      "    - proxying from local port $sourcePort to target $targetHost:$targetPort");

  if (webHost != null && webHost.isNotEmpty) {
    webDirectory = new VirtualDirectory(webHost);
    print("    - Web server active. Serving: $webHost");
  }
  try {
    HttpServer server;
    if (certPath != null && certPath.isNotEmpty) {
      SecurityContext secureContext = new SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
      server = await HttpServer.bindSecure(
          InternetAddress.anyIPv4, sourcePort, secureContext);
      print("    - Running in encrypted HTTPS (wss://) mode using: " +
          certPath +
          ", " +
          keyPath);
    } else {
      server = await HttpServer.bind(InternetAddress.anyIPv4, sourcePort);
      print("    - Running in unencrypted HTTP (ws://) mode");
    }

    print('    - Listening on port ${server.port} for HTTP request ...');

    await for (HttpRequest request in server) {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Headers',
          'Origin, X-Requested-With, Content-Type, Accept');

      if (request.uri.path.startsWith('/websockify')) {
        await serverWebSocketRequest(request);
      } else {
        if (webDirectory != null) {
          await webDirectory.serveRequest(request);
        } else {
          request.response.statusCode = HttpStatus.FORBIDDEN;
          request.response.write('403 Permission Denied');
        }
        request.response.close();
      }
    }
  } catch (e) {
    print(e);
    exit(-1);
  }
}

Future serverWebSocketRequest(HttpRequest request) async {
  try {
    print('Serving websocket...');
    request.response.headers.clear();
    request.response.headers.set('Sec-WebSocket-Protocol', 'binary');
    request.response.headers.set('Sec-WebSocket-Version', '13');

    // Setup the web socket connection
    WebSocket client;

    if (WebSocketTransformer.isUpgradeRequest(request)) {
      client = await WebSocketTransformer.upgrade(request);

      // Setup a new tcp socket connection
      Socket target = await Socket.connect(targetHost, targetPort);

      client.listen((data) => handleWebSocketData(data, target),
          onDone: () => handleWebSocketDone(target),
          onError: (error) => handleWebSocketError(error, target),
          cancelOnError: true);

      print('WebSocket connection...');
      print('Protocol: ${client.protocol}');

      target.listen((data) => handleSocketData(data, target, client),
          onDone: () => handleSocketDone(client),
          onError: (error) => handleSocketError(error, target, client),
          cancelOnError: true);

      print('Socket connected to target: ${target.address.host}:$targetPort');
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
