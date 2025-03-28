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
  bool _isFrontCamera = true;


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

  String? socketID ;

  void _connectSocket() {
    _socket = IO.io('http://192.168.0.123:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket!.connect();
    // _socket!.emit("connection", (data) => log(data.toString(), name: "From Connection route"),);
    _socket!.on("id", (data) {
      log(data.toString(), name: "Socket ID recieved");
        socketID = data.toString();
      log(socketID.toString(), name: "Socket from Var");
    });


    _socket!.on('offer', (data) {
      
      _handleOffer(data);
    });
    _socket!.on('answer', (data) {
      _handleAnswer(data);
    });
    _socket!.on('ice-candidate', (data) {
      _handleIceCandidate(data);
    });
  }

Future<void> _loadDevices() async {
  if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
    await Permission.camera.request();
    await Permission.microphone.request();
  }
  
  final devices = await navigator.mediaDevices.enumerateDevices();
  
  String? frontCameraId;
  String? backCameraId;
  
  for (var device in devices) {
    if (device.kind == 'videoinput') {
      if (device.label.toLowerCase().contains('front')) {
        frontCameraId = device.deviceId;
      } else if (device.label.toLowerCase().contains('back')) {
        backCameraId = device.deviceId;
      }
    }
  }
  
  setState(() {
    _devices = devices;
    _selectedVideoInputId = frontCameraId ?? (backCameraId ?? _devices.firstWhere((d) => d.kind == 'videoinput', orElse: () => _devices.first).deviceId);
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

    await _getUserMedia();

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

    setState(() {});
  }

Future<void> _getUserMedia() async {
  final Map<String, dynamic> mediaConstraints = {
    'audio': {'deviceId': _selectedAudioInputId},
    'video': {
      'facingMode': _isFrontCamera ? 'user' : 'environment',
      'deviceId': _selectedVideoInputId,
      'width': 1280,
      'height': 720
    }
  };

  try {
    // Stop all tracks of the previous stream
    await _localStream?.dispose();
    _localStream = null;

    var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = stream;
    _localRenderer.srcObject = _localStream;

    // Add tracks to peer connection
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
  } catch (e) {
    log('Error getting user media: $e');
  }
}

 
void _switchCamera() async {
  if (_localStream == null) return;

  _isFrontCamera = !_isFrontCamera;
  
  // Reuse the logic from _loadDevices to find camera IDs
  String? frontCameraId;
  String? backCameraId;
  
  for (var device in _devices) {
    if (device.kind == 'videoinput') {
      if (device.label.toLowerCase().contains('front')) {
        frontCameraId = device.deviceId;
      } else if (device.label.toLowerCase().contains('back')) {
        backCameraId = device.deviceId;
      }
    }
  }
  
  // Update _selectedVideoInputId based on the new camera selection
  _selectedVideoInputId = _isFrontCamera 
      ? (frontCameraId ?? _selectedVideoInputId)
      : (backCameraId ?? _selectedVideoInputId);

  await _getUserMedia();

  // Explicitly update the local renderer
  _localRenderer.srcObject = _localStream;

  // Replace tracks in peer connection
  var senders = await _peerConnection!.getSenders();
  var videoTrack = _localStream!.getVideoTracks().first;
  var videoSender = senders.firstWhere((sender) => sender.track?.kind == 'video');
  await videoSender.replaceTrack(videoTrack);

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
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Call'),
        actions: [
           IconButton(
            icon: Icon(_isFrontCamera ? Icons.camera_front : Icons.camera_rear),
            onPressed: _inCalling ? _switchCamera : null,
          ),
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
              child: 
                   Stack(
                    children: [
                       Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black)
                        ),
                        child: RTCVideoView(_remoteRenderer),
                      ),
                      Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black)
                        ),
                        height: height/5.5,
                        width: width/5,
                        child: RTCVideoView(_localRenderer),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          margin: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey)
                          ),
                          height: 75,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Container(
                                height: 40,
                                width: 80,
                                
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.video_camera_back,color: Colors.white,)),
                                Container(
                                height: 40,
                                width: 80,
                                
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.mic,color: Colors.white,)),
                              // Icon(Icons.people_sharp),
                              Container(
                                height: 40,
                                width: 80,
                                
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.people_alt_rounded,color: Colors.white,)),
                              Container(
                                height: 40,
                                width: 100,
                                
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.phone_disabled_rounded,color: Colors.white,))
                            ],
                          ),
                        ),
                      )
                    ],
                  )
                
                
              
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