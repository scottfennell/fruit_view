#!/usr/bin/env python3
"""
Video decode sidecar for fruit_view.

Decodes a video source with GStreamer and streams raw RGBA frames over a local
TCP connection to the Godot client.

Frame protocol (sent for each decoded frame):
    [width:  u32 little-endian]  4 bytes
    [height: u32 little-endian]  4 bytes
    [pixels: RGBA8]              width * height * 4 bytes

The sidecar listens as a TCP server. Godot connects as the client. If the
client disconnects the sidecar waits for a new connection (supports the
Godot-side reconnect loop without restarting the process).

Usage:
    python3 sidecar/video_sidecar.py --port 9001 --url rtsp://192.168.1.100:8554/stream
    python3 sidecar/video_sidecar.py --port 9001 --file /path/to/test.mp4

Requirements (Debian/Ubuntu/Orange Pi):
    sudo apt install python3-gi gstreamer1.0-plugins-base \\
         gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \\
         gstreamer1.0-libav gir1.2-gst-plugins-base-1.0
"""

import argparse
import socket
import struct
import sys
import threading

try:
    import gi
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst, GLib
    Gst.init(None)
except (ImportError, ValueError) as exc:
    print(f"ERROR: GStreamer Python bindings unavailable: {exc}", file=sys.stderr)
    print("Install python3-gi and the GStreamer gir packages.", file=sys.stderr)
    sys.exit(1)


class FrameSender:
    """Manages one GStreamer pipeline and streams frames to a TCP client."""

    def __init__(self, port: int, source_uri: str, is_file: bool) -> None:
        self._port       = port
        self._source_uri = source_uri
        self._is_file    = is_file
        self._client: socket.socket | None = None
        self._client_lock = threading.Lock()
        self._pipeline   = None
        self._loop: GLib.MainLoop | None = None

    # ── Public entry point ────────────────────────────────────────────────────

    def run(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", self._port))
        server.listen(1)
        print(f"[sidecar] Listening on 127.0.0.1:{self._port}", flush=True)

        try:
            while True:
                conn, addr = server.accept()
                print(f"[sidecar] Client connected from {addr}", flush=True)
                with self._client_lock:
                    self._client = conn
                self._run_pipeline()
                with self._client_lock:
                    self._client = None
                conn.close()
                print("[sidecar] Client disconnected — waiting for reconnect …",
                      flush=True)
        except KeyboardInterrupt:
            print("[sidecar] Shutting down.", flush=True)
        finally:
            server.close()

    # ── Pipeline lifecycle ────────────────────────────────────────────────────

    def _build_pipeline_string(self) -> str:
        if self._is_file:
            src = f'filesrc location="{self._source_uri}" ! decodebin'
        else:
            src = (
                f'rtspsrc location="{self._source_uri}" latency=0 '
                f'protocols=tcp '
                f'! rtph264depay ! avdec_h264'
            )
        # max-buffers=1 drop=true: always deliver the latest frame, never queue.
        return (
            f'{src}'
            f' ! videoconvert'
            f' ! video/x-raw,format=RGBA'
            f' ! appsink name=sink emit-signals=true max-buffers=1 drop=true'
        )

    def _run_pipeline(self) -> None:
        pipeline_str = self._build_pipeline_string()
        print(f"[sidecar] Pipeline: {pipeline_str}", flush=True)

        self._pipeline = Gst.parse_launch(pipeline_str)
        sink = self._pipeline.get_by_name("sink")
        sink.connect("new-sample", self._on_new_sample)

        bus = self._pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_bus_message)

        self._loop = GLib.MainLoop()
        self._pipeline.set_state(Gst.State.PLAYING)
        try:
            self._loop.run()
        finally:
            self._pipeline.set_state(Gst.State.NULL)
            self._pipeline = None
            self._loop = None

    # ── GStreamer callbacks ───────────────────────────────────────────────────

    def _on_new_sample(self, sink) -> Gst.FlowReturn:
        sample = sink.emit("pull-sample")
        if sample is None:
            return Gst.FlowReturn.ERROR

        buf      = sample.get_buffer()
        caps     = sample.get_caps()
        st       = caps.get_structure(0)
        width    = st.get_int("width").value
        height   = st.get_int("height").value

        ok, map_info = buf.map(Gst.MapFlags.READ)
        if not ok:
            return Gst.FlowReturn.ERROR
        frame_bytes = bytes(map_info.data)
        buf.unmap(map_info)

        header  = struct.pack("<II", width, height)
        payload = header + frame_bytes

        with self._client_lock:
            if self._client is not None:
                try:
                    self._client.sendall(payload)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    # Client gone — stop the pipeline so the accept loop can restart.
                    if self._loop and self._loop.is_running():
                        GLib.idle_add(self._loop.quit)

        return Gst.FlowReturn.OK

    def _on_bus_message(self, _bus, message) -> None:
        if message.type == Gst.MessageType.ERROR:
            err, dbg = message.parse_error()
            print(f"[sidecar] GStreamer error: {err}\n  debug: {dbg}",
                  file=sys.stderr, flush=True)
            if self._loop and self._loop.is_running():
                GLib.idle_add(self._loop.quit)
        elif message.type == Gst.MessageType.EOS:
            print("[sidecar] End of stream.", flush=True)
            if self._loop and self._loop.is_running():
                GLib.idle_add(self._loop.quit)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="fruit_view GStreamer video sidecar"
    )
    parser.add_argument(
        "--port", type=int, default=9001,
        help="Local TCP port to listen on (default: 9001)"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--url",  metavar="RTSP_URL",  help="RTSP stream URL")
    group.add_argument("--file", metavar="FILE_PATH", help="Local video file path")
    args = parser.parse_args()

    is_file = args.file is not None
    source  = args.file if is_file else args.url

    FrameSender(port=args.port, source_uri=source, is_file=is_file).run()


if __name__ == "__main__":
    main()
