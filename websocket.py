# Copyright (C) 2024 Connor Davis
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import errno
import os
import socket
import ssl

from websockets.uri import parse_uri
from websockets.client import ClientProtocol

class WebSocketConnection():
    def __init__(self, ws_uri, ssl_context=None):
        self._ws_uri = parse_uri(ws_uri)
        self._ws_protocol = ClientProtocol(self._ws_uri)
        self._sock = None
        self._ssl_context = ssl_context
        self._host = self._ws_uri.host
        self._port = self._ws_uri.port
        self._need_close = False

    def open(self):
        if self._ws_uri.secure:
            if self._ssl_context is None:
                self._ssl_context = ssl.create_default_context()

            try:
                self._sock = self._ssl_context.wrap_socket(
                    self._sock, server_hostname=self._host
                )
            except ssl.SSLError as e:
                print(f'ERROR: ssl wrap_socket failed with {e.reason}')
                sys.exit(42)
        else:
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        try:
            self._sock.connect((self._host, self._port))
        except socket.error as e:
            print(f'ERROR: connect failed with {os.strerror(e.errno)}')
            sys.exit(e.errno)

        # Open the websocket connection
        handshake = self._ws_protocol.connect()
        self._ws_protocol.send_request(handshake)
        self.send_data()

    def send_data(self):
        for data in self._ws_protocol.data_to_send():
            if data:
                self._sock.sendall(data)
            else:
                print("Calling sock.shutdown!")
                self._sock.shutdown(socket.SHUT_WR)

    def recv_data(self):
        try:
            data = self._sock.recv(65536)
        except OSError:
            data = b""

        if data:
            self._ws_protocol.receive_data(data)
        else:
            self._ws_protocol.receive_eof()
            self._need_close = True

    def events_received(self):
        return self._ws_protocol.events_received()

    def close(self):
        self._ws_protocol.send_close(1000)
        self.send_data()
        self._sock.close()
