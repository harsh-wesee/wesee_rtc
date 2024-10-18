import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: CallScreen()
    );
  }
}



class CallScreen extends StatefulWidget {
  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  IO.Socket? _socket;
  bool _inCalling = false;
  List<MediaDeviceInfo> _devices = [];
  String? _selectedVideoInputId;
  String? _selectedAudioInputId;

  @override
  void initState() {
    super.initState();
    initRenderers();
    _connectSocket();
    _loadDevices();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();
    _socket?.disconnect();
    super.dispose();
  }

  void initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _connectSocket() {
    _socket = IO.io('http://10.0.2.2:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket!.connect();
    _socket!.on('connect', (_) => log('Connected to server'));
    _socket!.on('offer', (data) => _handleOffer(data));
    _socket!.on('answer', (data) => _handleAnswer(data));
    _socket!.on('ice-candidate', (data) => _handleIceCandidate(data));
  }

  Future<void> _loadDevices() async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await Permission.camera.request();
      await Permission.microphone.request();
    }
    final devices = await navigator.mediaDevices.enumerateDevices();
    setState(() {
      _devices = devices;
      _selectedVideoInputId = _devices
          .firstWhere((d) => d.kind == 'videoinput', orElse: () => _devices.first)
          .deviceId;
      _selectedAudioInputId = _devices
          .firstWhere((d) => d.kind == 'audioinput', orElse: () => _devices.first)
          .deviceId;
    });
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;
    final config = {
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302']}
      ]
    };

    _peerConnection = await createPeerConnection(config);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {'deviceId': _selectedAudioInputId},
      'video': {
        'deviceId': _selectedVideoInputId,
        'width': 1280,
        'height': 720
      }
    });

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (candidate) {
      _socket!.emit('ice-candidate', {
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    _localRenderer.srcObject = _localStream;
    setState(() {});
  }

  void _handleOffer(dynamic data) async {
    log("handling offer");
    await _createPeerConnection();  
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _socket!.emit('answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
    log("Handle function called");
  }

  void _handleAnswer(dynamic data) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
  }

  void _handleIceCandidate(dynamic data) async {
    final candidate = RTCIceCandidate(
      data['candidate']['candidate'],
      data['candidate']['sdpMid'],
      data['candidate']['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(candidate);
  }

  void _makeCall() async {
    await _createPeerConnection();
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socket!.emit('offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });

    setState(() {
      _inCalling = true;
    });
  }

  void _endCall() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _peerConnection = null; 
    await _peerConnection?.close();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    setState(() {
      _inCalling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WebRTC Call'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (deviceId) {
              setState(() => _selectedVideoInputId = deviceId);
            },
            itemBuilder: (BuildContext context) {
              return _devices
                  .where((device) => device.kind == 'videoinput')
                  .map((device) {
                return PopupMenuItem<String>(
                  value: device.deviceId,
                  child: Text(device.label),
                );
              }).toList();
            },
            icon: Icon(Icons.videocam),
          ),
          PopupMenuButton<String>(
            onSelected: (deviceId) {
              setState(() => _selectedAudioInputId = deviceId);
            },
            itemBuilder: (BuildContext context) {
              return _devices
                  .where((device) => device.kind == 'audioinput')
                  .map((device) {
                return PopupMenuItem<String>(
                  value: device.deviceId,
                  child: Text(device.label),
                );
              }).toList();
            },
            icon: Icon(Icons.mic),
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              width: MediaQuery.of(context).size.width,
              color: Colors.white10,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      decoration: BoxDecoration(color: Colors.black54),
                      child: RTCVideoView(_localRenderer),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      decoration: BoxDecoration(color: Colors.black54),
                      child: RTCVideoView(_remoteRenderer),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _endCall : _makeCall,
        tooltip: _inCalling ? 'End Call' : 'Start Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}