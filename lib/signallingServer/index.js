const express = require('express');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send('WebRTC Signaling Server');
});

io.on('connection', (socket) => {
  console.log('A user connected');

  socket.on('offer', (data) => {
    socket.broadcast.emit('offer', data);
    console.log("offer send to reciever");
  });

  socket.on('answer', (data) => {
    socket.broadcast.emit('answer', data);
    console.log("offer aceepted")
  });

  socket.on('ice-candidate', (data) => {
    socket.broadcast.emit('ice-candidate', data);
    console.log("ice candidate attempted")
  });

  socket.on('disconnect', () => {
    console.log('User disconnected');
  });
});

server.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});