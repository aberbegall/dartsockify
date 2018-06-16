/// A socket proxy specification.
class SocketProxy { 
  int sourcePort;
  String targetHost;
  int targetPort;

  SocketProxy(this.sourcePort, this.targetHost, this.targetPort);
}