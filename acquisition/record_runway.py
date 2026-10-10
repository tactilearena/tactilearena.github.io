"""Record four tactile boards + overhead cameras on one shared clock (the
paper's runway_three_cams.py). Edit ports, cameras and board settings at the
bottom. BoardN_buffer_overflows is always 0 (check disabled); cameras run
below 30 fps, so use the saved frame timestamps.
"""
import serial
import struct
import time
import threading
import queue
import numpy as np
from datetime import datetime
import os
from scipy.io import savemat
import cv2


class TactileDataRecorder:
    def __init__(self, ports):
        self.ports = ports
        self.connections = {}
        self.connect_all_boards()

        # Data storage
        self.recorded_data = {}
        self.recording = False
        self.start_time = None
        self.shared_start_time = None  # Single shared timestamp

    def connect_all_boards(self):
        print("=== Connecting to all boards ===")
        for i, port in enumerate(self.ports):
            try:
                # Use longer timeout initially for connection/config
                ser = serial.Serial(port, 115200, timeout=2.0)
                try:
                    ser.set_buffer_size(rx_size=1000000, tx_size=1000000)
                except:
                    pass

                time.sleep(0.5)
                board_name = f'Board_{i + 1}'
                port_num = i + 1

                self.connections[board_name] = {
                    'serial': ser,
                    'port': port,
                    'port_num': port_num,
                    'connected': True,
                    'board_id': None
                }
                print(f"✓ Connected to {board_name} on {port}")
            except Exception as e:
                print(f"✗ Failed to connect to {port}: {e}")
                self.connections[f'Board_{i + 1}'] = {
                    'connected': False,
                    'port_num': i + 1
                }

    def configure_board(self, board_name, M_value, threshold, digipot):
        """Configure a board with M_value, threshold, and digipot settings (matches square code)"""
        if not self.connections[board_name]['connected']:
            print(f"[{board_name}] Not connected, skipping configuration")
            return False

        try:
            ser = self.connections[board_name]['serial']
            port_num = self.connections[board_name]['port_num']

            # Send configuration: M_value threshold digipot
            config_str = f"{M_value} {threshold} {digipot}\n"
            ser.write(config_str.encode())
            print(f"[{board_name}] Sent config: {config_str.strip()}")

            # Wait for "OK" response
            ok_buffer = bytearray()
            start_time = time.time()
            config_ok = False

            while (time.time() - start_time) < 2.0:  # 2 second timeout
                if ser.in_waiting > 0:
                    byte = ser.read(1)
                    ok_buffer.append(byte[0])

                    # Check if we have "OK\n" or "OK\r\n"
                    try:
                        text = ok_buffer.decode('utf-8', errors='ignore')
                        if 'OK' in text:
                            print(f"[{board_name}] ✓ Configuration confirmed")
                            config_ok = True
                            break
                    except:
                        pass

                    # Keep buffer small
                    if len(ok_buffer) > 100:
                        ok_buffer = ok_buffer[-50:]

            if not config_ok:
                print(f"[{board_name}] ⚠ No OK received (continuing anyway)")

            # Minimal delay
            time.sleep(0.1)
            ser.reset_input_buffer()

            # Set shorter timeout for data streaming
            ser.timeout = 0.01

            print(f"[{board_name}] Ready to receive data")
            return True

        except Exception as e:
            print(f"[{board_name}] Failed to configure: {e}")
            return False

    def data_recorder_worker(self, board_name, stop_event, start_signal, video_recorder):
        """Worker thread to record data from one board"""
        if not self.connections[board_name]['connected']:
            return

        ser = self.connections[board_name]['serial']
        port_num = self.connections[board_name]['port_num']

        # Store as separate lists
        timestamps = []
        pixel_indices = []
        pixel_values = []
        board_ids = []

        frame_count = 0
        first_board_id = None
        last_print_time = time.time()
        buffer_overflow_count = 0
        pause_count = 0  # Track how many times we paused for disk stalls

        SYNC_MARKER = 0xDEADBEEF
        BUFFER_WARNING_THRESHOLD = 80000  # Warn if buffer exceeds 50KB
        BUFFER_FLUSH_THRESHOLD = 100000  # Flush if buffer exceeds 80KB

        # Wait for start signal
        print(f"[{board_name}] Waiting for start signal...")
        start_signal.wait()

        # Use shared start time
        local_start_time = self.shared_start_time

        print(f"[{board_name}] Started recording at t={local_start_time:.6f}")

        while not stop_event.is_set():
            try:
                # # BUFFER MANAGEMENT: Check buffer size before reading
                # buffer_size = ser.in_waiting
                #
                # if buffer_size > BUFFER_FLUSH_THRESHOLD:
                #     # Critical: buffer is too full, clear it to prevent old data
                #     ser.reset_input_buffer()
                #     buffer_overflow_count += 1
                #     print(
                #         f"[{board_name}] ⚠ BUFFER OVERFLOW! Cleared {buffer_size} bytes (overflow #{buffer_overflow_count})")
                #     continue
                # elif buffer_size > BUFFER_WARNING_THRESHOLD:
                #     print(f"[{board_name}] ⚠ Buffer warning: {buffer_size} bytes pending")

                sync_data = ser.read(4)
                if len(sync_data) != 4:
                    continue

                sync = struct.unpack('<I', sync_data)[0]

                if sync != SYNC_MARKER:
                    # Invalid sync - clear buffer to resync
                    ser.reset_input_buffer()
                    continue

                header_data = ser.read(6)
                if len(header_data) != 6:
                    # Incomplete header - clear buffer to resync
                    ser.reset_input_buffer()
                    continue

                board_id, count, frame_num = struct.unpack('<HHH', header_data)

                # Capture timestamp AFTER successfully reading header (valid frame confirmed)
                timestamp = time.time() - local_start_time

                # Store the actual board_id from the packet
                if first_board_id is None:
                    first_board_id = board_id
                    self.connections[board_name]['board_id'] = board_id
                    print(f"[{board_name}] First packet received - Board ID: {board_id}")

                frame_indices_list = []
                frame_values_list = []

                if count > 0:
                    expected_bytes = count * 4
                    pixel_data = ser.read(expected_bytes)

                    if len(pixel_data) == expected_bytes:
                        raw_array = np.frombuffer(pixel_data, dtype='<H')
                        indices = raw_array[0::2]
                        values = raw_array[1::2]

                        # Filter out invalid indices (like square code does)
                        mask = (indices != 0xFFFF) & (indices != 0xFFFE) & (indices < 4096)
                        frame_indices_list = indices[mask].tolist()
                        frame_values_list = values[mask].tolist()
                    else:
                        # Incomplete pixel data - clear buffer to resync
                        ser.reset_input_buffer()
                        continue

                # Successfully read frame - store it with the timestamp captured at the start
                timestamps.append(timestamp)
                pixel_indices.append(frame_indices_list)
                pixel_values.append(frame_values_list)
                board_ids.append(board_id)

                frame_count += 1

                # BUFFER MANAGEMENT: Periodically clear excess buffered data
                # This prevents old data from accumulating
                if frame_count % 100 == 0:  # Check every 100 frames
                    remaining_buffer = ser.in_waiting
                    if remaining_buffer > 10000:  # If more than 10KB waiting
                        # We're falling behind - clear excess
                        ser.reset_input_buffer()
                        print(f"[{board_name}] Cleared {remaining_buffer} bytes of excess buffer data")

                # Periodic status update
                current_time = time.time()
                if current_time - last_print_time >= 5.0:
                    elapsed = timestamp
                    fps = frame_count / elapsed if elapsed > 0 else 0
                    avg_pixels_per_frame = np.mean([len(indices) for indices in pixel_indices]) if pixel_indices else 0
                    print(f"[{board_name}] {frame_count} frames, {elapsed:.1f}s, "
                          f"{fps:.1f} FPS, avg {avg_pixels_per_frame:.0f} pixels/frame, "
                          f"buffer: {ser.in_waiting} bytes, pauses: {pause_count}, overflows: {buffer_overflow_count}")
                    last_print_time = current_time

            except serial.SerialException as e:
                print(f"[{board_name}] Serial error: {e}")
                time.sleep(0.1)
            except Exception as e:
                print(f"[{board_name}] Error: {e}")
                time.sleep(0.01)

        self.recorded_data[board_name] = {
            'total_frames': frame_count,
            'timestamps': timestamps,
            'pixel_indices': pixel_indices,
            'pixel_values': pixel_values,
            'board_ids': board_ids,
            'buffer_overflows': buffer_overflow_count,
            'stall_pauses': pause_count
        }

        print(
            f"[{board_name}] Finished recording: {frame_count} frames, {pause_count} stall pauses, {buffer_overflow_count} buffer overflows")

    def start_recording(self, duration, M_value=400, threshold=150, digipot=50, filename=None, video_recorder=None):
        self.M_value = M_value
        self.threshold = threshold
        self.digipot = digipot

        print(f"\n{'=' * 60}")
        print(f"=== Starting Data Recording ===")
        print(f"{'=' * 60}")
        print(f"Configuration: M={M_value}, Threshold={threshold}, Digipot={digipot}")
        print(f"Duration: {duration} seconds")
        print(f"{'=' * 60}\n")

        print("Configuring boards...")
        configured_count = 0
        for board_name in self.connections:
            if self.connections[board_name]['connected']:
                success = self.configure_board(board_name, M_value, threshold, digipot)
                if success:
                    configured_count += 1

        if configured_count == 0:
            print("\n✗ No boards were successfully configured!")
            return None

        print(f"\n✓ Successfully configured {configured_count} board(s)")

        print("\nWaiting for boards to stabilize...")
        time.sleep(1.5)

        print("Clearing serial buffers...")
        for board_name in self.connections:
            if self.connections[board_name]['connected']:
                self.connections[board_name]['serial'].reset_input_buffer()

        # Initialize video
        video_threads = []
        video_ready_event = threading.Event()
        video_start_signal = threading.Event()

        if video_recorder is not None:
            print(f"\n{'=' * 60}")
            print("=== Initializing video recording ===")
            print(f"{'=' * 60}")
            video_recorder.set_recorder(self)  # Pass reference for shared timing

            if video_recorder.initialize_cameras():
                # Show camera preview and wait for user confirmation
                if not video_recorder.show_preview_and_confirm():
                    print("Recording cancelled by user")
                    video_recorder.cleanup()
                    return None

                video_threads = video_recorder.create_recording_threads(
                    duration, video_ready_event, video_start_signal
                )

                print("Waiting for all cameras to be ready...")
                video_ready_event.wait(timeout=10)
                print("✓ All cameras ready!")
            else:
                print("⚠ Warning: Video initialization failed")
                video_recorder = None

        self.recorded_data = {}
        self.recording = True

        threads = []
        stop_event = threading.Event()
        sensor_start_signal = threading.Event()

        # Create sensor threads
        for board_name in self.connections:
            if self.connections[board_name]['connected']:
                thread = threading.Thread(
                    target=self.data_recorder_worker,
                    args=(board_name, stop_event, sensor_start_signal, video_recorder)
                )
                thread.daemon = True
                thread.start()
                threads.append((thread, board_name))

        # CRITICAL: Set shared start time BEFORE signaling
        print(f"\n{'=' * 60}")
        print("=== Starting synchronized recording ===")
        print(f"{'=' * 60}")
        self.shared_start_time = time.time()
        self.start_time = self.shared_start_time

        print(f"Shared start time: {self.shared_start_time:.6f}")

        # Signal all threads simultaneously
        sensor_start_signal.set()
        if video_threads:
            video_start_signal.set()

        print("\n✓ All recording started!")
        print("Press Ctrl+C to stop recording early\n")

        # Main recording loop - use shared start time with strict timing
        last_update = self.shared_start_time
        deadline = self.shared_start_time + duration

        try:
            while True:
                current_time = time.time()

                # STRICT: Check if we've exceeded duration
                if current_time >= deadline:
                    break

                # Only print status every 1 second (not sleep for 1 second!)
                if current_time - last_update >= 1.0:
                    elapsed = current_time - self.shared_start_time
                    remaining = duration - elapsed
                    print(f"Recording... {elapsed:.1f}s / {duration}s (remaining: {remaining:.1f}s)")
                    last_update = current_time

                # Sleep briefly to prevent CPU spinning
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n\n⚠ Recording interrupted by user")

        print(f"\n{'=' * 60}")
        print("=== Stopping recording ===")
        print(f"{'=' * 60}")
        stop_event.set()
        self.recording = False

        actual_duration = time.time() - self.start_time

        if actual_duration > duration + 1.0:  # Allow 1 second tolerance
            print(f"⚠ WARNING: Recording exceeded target duration by {actual_duration - duration:.1f}s")

        print("Waiting for sensor threads to finish...")
        for thread, board_name in threads:
            thread.join(timeout=2.0)  # Max 2 seconds per thread
            if thread.is_alive():
                print(f"⚠ Warning: {board_name} thread did not finish cleanly")

        if video_threads:
            print("Waiting for video recording threads to finish...")
            for i, thread in enumerate(video_threads):
                thread.join(timeout=5.0)  # Max 5 seconds per camera
                if thread.is_alive():
                    print(f"⚠ Warning: Camera thread {i} is still running after timeout")
            video_recorder.cleanup()

        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"runway_tactile_data_{timestamp}_M{M_value}_T{threshold}_D{digipot}.mat"

        self.save_data(filename, actual_duration, video_recorder)
        return filename

    def save_data(self, filename, duration, video_recorder):
        total_frames = 0
        total_pixels = 0
        total_overflows = 0

        for board_name, board_data in self.recorded_data.items():
            total_frames += board_data['total_frames']
            total_overflows += board_data.get('buffer_overflows', 0)
            for frame_pixels in board_data['pixel_values']:
                total_pixels += len(frame_pixels)

        mat_data = {}
        mat_data['M'] = self.M_value
        mat_data['threshold'] = self.threshold
        mat_data['digipot'] = self.digipot
        mat_data['duration'] = duration
        mat_data['shared_start_time'] = self.shared_start_time

        for board_name, board_data in self.recorded_data.items():
            clean_name = board_name.replace('_', '')
            mat_data[f'{clean_name}_timestamps'] = np.array(board_data['timestamps'])
            mat_data[f'{clean_name}_pixel_indices'] = board_data['pixel_indices']
            mat_data[f'{clean_name}_pixel_values'] = board_data['pixel_values']
            mat_data[f'{clean_name}_board_ids'] = np.array(board_data.get('board_ids', []), dtype=np.uint16)
            mat_data[f'{clean_name}_buffer_overflows'] = board_data.get('buffer_overflows', 0)

        # Save individual frame timestamps for each camera as numpy arrays
        if video_recorder and hasattr(video_recorder, 'camera_data'):
            for cam_idx, cam_data in video_recorder.camera_data.items():
                if cam_data['frame_timestamps']:
                    # Store timestamps as numpy array for easy synchronization
                    # These timestamps are relative to shared_start_time, same as sensor timestamps
                    mat_data[f'camera{cam_idx}_frame_timestamps'] = np.array(cam_data['frame_timestamps'],
                                                                             dtype=np.float64)
                    mat_data[f'camera{cam_idx}_total_frames'] = len(cam_data['frame_timestamps'])
                    mat_data[f'camera{cam_idx}_dropped_frames'] = cam_data.get('dropped_frames', 0)
                    mat_data[f'camera{cam_idx}_actual_fps'] = cam_data.get('actual_fps', 30.0)
                    if 'video_filename' in cam_data:
                        mat_data[f'camera{cam_idx}_filename'] = cam_data['video_filename']

                    # Also store frame indices for convenience
                    mat_data[f'camera{cam_idx}_frame_indices'] = np.arange(len(cam_data['frame_timestamps']),
                                                                           dtype=np.int32)

        try:
            savemat(filename, mat_data)
            file_size = os.path.getsize(filename) / (1024 * 1024)

            print(f"\n{'=' * 60}")
            print(f"=== Recording Complete ===")
            print(f"{'=' * 60}")
            print(f"Data saved to: {filename}")
            print(f"File size: {file_size:.1f} MB")
            print(f"Duration: {duration:.1f} seconds")
            print(f"Total sensor frames: {total_frames}")
            print(f"Total pixels sampled: {total_pixels}")

            if total_overflows > 0:
                print(f"\n⚠ WARNING: {total_overflows} total buffer overflows detected!")
                print("  This may indicate data loss or desynchronization.")

            print("\nPer-board summary:")
            for board_name, board_data in self.recorded_data.items():
                if duration > 0:
                    fps = board_data['total_frames'] / duration
                else:
                    fps = 0
                bid = self.connections[board_name].get('board_id', 'Unknown')
                avg_pixels = np.mean([len(indices) for indices in board_data['pixel_indices']]) if board_data[
                    'pixel_indices'] else 0
                overflows = board_data.get('buffer_overflows', 0)
                overflow_str = f" ⚠ {overflows} overflows" if overflows > 0 else ""
                print(f"  {board_name} (ID {bid}): {board_data['total_frames']} frames "
                      f"({fps:.1f} FPS, avg {avg_pixels:.0f} pixels/frame){overflow_str}")

            if video_recorder and hasattr(video_recorder, 'camera_data'):
                print("\nPer-camera summary:")
                for cam_idx, cam_data in video_recorder.camera_data.items():
                    frames = len(cam_data['frame_timestamps'])
                    fps = frames / duration if duration > 0 else 0
                    dropped = cam_data.get('dropped_frames', 0)
                    dropped_str = f", {dropped} dropped" if dropped > 0 else ""
                    actual_fps = cam_data.get('actual_fps', 0)
                    print(
                        f"  Camera {cam_idx}: {frames} frames ({fps:.1f} FPS{dropped_str}, actual: {actual_fps:.2f} FPS) - {cam_data.get('video_filename', 'N/A')}")

            print(f"{'=' * 60}\n")

        except Exception as e:
            print(f"✗ Error saving data: {e}")
            import traceback
            traceback.print_exc()

    def cleanup(self):
        print("\nClosing connections...")
        for board_name in self.connections:
            if self.connections[board_name].get('connected'):
                try:
                    self.connections[board_name]['serial'].close()
                    print(f"  ✓ Closed {board_name}")
                except Exception as e:
                    print(f"  ✗ Error closing {board_name}: {e}")


class MultiCameraRecorder:
    def __init__(self, camera_indices=[0, 1, 2], width=1920, height=1080, fps=30.0, show_preview=False):
        self.camera_indices = camera_indices
        self.width = width
        self.height = height
        self.fps = fps
        self.show_preview = show_preview
        self.preview_enabled = False

        # Storage for each camera
        self.caps = {}
        self.outs = {}
        self.camera_data = {}
        self.grabber_stop_events = {}  # Stop events for grabber threads

        self.recorder = None  # Reference to parent recorder

        # SYNCHRONIZATION: Event to signal disk stalls to sensor threads
        self.disk_stall_event = threading.Event()
        self.disk_stall_event.set()  # Start with no stall (sensors can run)

    def set_recorder(self, recorder):
        self.recorder = recorder

    def initialize_cameras(self):
        """Initialize all cameras"""
        try:
            print(f"Opening {len(self.camera_indices)} cameras...")

            for cam_idx in self.camera_indices:
                print(f"  Initializing camera {cam_idx}...")

                # Try AVFoundation first (macOS), then fall back
                cap = cv2.VideoCapture(cam_idx, cv2.CAP_AVFOUNDATION)

                if not cap.isOpened():
                    print(f"    AVFoundation failed for camera {cam_idx}, trying default backend...")
                    cap = cv2.VideoCapture(cam_idx)

                if not cap.isOpened():
                    print(f"    ✗ Error: Could not open camera {cam_idx}")
                    continue

                # Set resolution and FPS
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
                cap.set(cv2.CAP_PROP_FPS, self.fps)

                # Disable autofocus
                cap.set(cv2.CAP_PROP_AUTOFOCUS, 0)

                actual_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                actual_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                actual_fps = cap.get(cv2.CAP_PROP_FPS)

                print(f"    ✓ Camera {cam_idx} opened: {actual_width}x{actual_height} @ {actual_fps} FPS")
                print(f"    ✓ Autofocus disabled")

                # Warm-up
                print(f"    Warming up camera {cam_idx}...")
                for i in range(30):
                    ret, frame = cap.read()
                    if not ret:
                        print(f"      ⚠ Warning: Failed to read frame {i + 1}/30 during warmup")
                    time.sleep(0.05)

                self.caps[cam_idx] = cap
                self.camera_data[cam_idx] = {
                    'frame_timestamps': [],
                    'video_filename': None,
                    'width': actual_width,
                    'height': actual_height,
                    'dropped_frames': 0
                }

                print(f"    ✓ Camera {cam_idx} initialized successfully!")

            if not self.caps:
                print("✗ Error: No cameras were successfully initialized")
                return False

            print(f"\n✓ Successfully initialized {len(self.caps)} cameras")
            return True

        except Exception as e:
            print(f"✗ Error initializing cameras: {e}")
            self.cleanup()
            return False

    def show_preview_and_confirm(self):
        """Show live preview of all cameras and wait for user confirmation"""
        print(f"\n{'=' * 60}")
        print("=== Camera Preview ===")
        print(f"{'=' * 60}")
        print("Displaying live camera feeds...")
        print("Instructions:")
        print("  - Turn off camera LEDs if needed")
        print("  - Press 'y' when ready to start recording")
        print("  - Press 'n' to cancel")
        print()

        while True:
            frames = []
            for cam_idx in sorted(self.caps.keys()):
                cap = self.caps[cam_idx]
                ret, frame = cap.read()
                if ret:
                    # Resize to a smaller size for preview grid
                    frame_resized = cv2.resize(frame, (400, 300))
                    # Label the frame
                    cv2.putText(frame_resized, f"Camera {cam_idx}", (20, 50),
                                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                    frames.append(frame_resized)

            if frames:
                # Display cameras in a single row
                grid = np.hstack(frames)
                cv2.imshow('Camera Preview - Press Y to continue, N to cancel', grid)

            key = cv2.waitKey(1) & 0xFF

            if key == ord('y') or key == ord('Y'):
                print("\n✓ User confirmed - closing preview window...")
                cv2.destroyAllWindows()
                # Force window closure and clear any pending events
                cv2.waitKey(1)
                # Clear camera buffers after preview
                for cam_idx in self.caps.keys():
                    self.caps[cam_idx].read()  # Discard any buffered frames
                print("✓ Preview closed - proceeding with recording")
                return True
            elif key == ord('n') or key == ord('N'):
                print("\n✗ User cancelled recording")
                cv2.destroyAllWindows()
                cv2.waitKey(1)
                return False

    def frame_grabber_thread(self, cam_idx, stop_event):
        """Continuously grab frames to keep buffer fresh and prevent lag"""
        cap = self.caps[cam_idx]
        print(f"Camera {cam_idx}: Frame grabber thread started")

        grab_count = 0
        while not stop_event.is_set():
            try:
                # BUFFER MANAGEMENT: Just grab, don't decode - this is fast
                # This prevents old frames from accumulating in the buffer
                success = cap.grab()
                if success:
                    grab_count += 1
                else:
                    time.sleep(0.001)  # Brief pause if grab failed
            except Exception as e:
                print(f"Camera {cam_idx} grabber error: {e}")
                time.sleep(0.001)

        print(f"Camera {cam_idx}: Frame grabber thread stopped (grabbed {grab_count} frames)")

    def record_camera(self, cam_idx, duration, ready_event, start_signal_event):
        """Record from a single camera"""
        try:
            if cam_idx not in self.caps:
                print(f"✗ Error: Camera {cam_idx} not initialized")
                return

            cap = self.caps[cam_idx]

            # Setup video writer
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            video_filename = f'camera_{cam_idx}_{timestamp}.mp4'

            actual_width = self.camera_data[cam_idx]['width']
            actual_height = self.camera_data[cam_idx]['height']

            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            out = cv2.VideoWriter(video_filename, fourcc, self.fps, (actual_width, actual_height))

            if not out.isOpened():
                print(f"✗ Error: Could not create video file for camera {cam_idx}")
                return

            self.camera_data[cam_idx]['video_filename'] = video_filename
            self.outs[cam_idx] = out

            # Start frame grabber thread to continuously clear buffer
            grabber_stop = threading.Event()
            self.grabber_stop_events[cam_idx] = grabber_stop
            grabber_thread = threading.Thread(
                target=self.frame_grabber_thread,
                args=(cam_idx, grabber_stop)
            )
            grabber_thread.daemon = True
            grabber_thread.start()

            # Wait for synchronized start signal
            print(f"Camera {cam_idx}: Ready, waiting for start signal...")
            start_signal_event.wait()

            # Use shared start time from recorder
            start_time = self.recorder.shared_start_time if self.recorder else time.time()

            print(f"Camera {cam_idx}: ✓ Recording NOW at t={start_time:.6f}")

            recorded_count = 0
            dropped_frames = 0
            last_status_time = start_time
            frame_write_times = []
            stall_count = 0

            # Target interval based on configured FPS
            target_interval = 1.0 / self.fps
            next_capture_time = start_time

            # STALL THRESHOLD: Consider it a severe stall if write takes >1 second
            STALL_THRESHOLD = 1.0

            while (time.time() - start_time) < duration:
                current_time = time.time()

                # Check if it's time to capture a frame
                if current_time >= next_capture_time:
                    write_start = time.time()

                    # Retrieve the most recent frame
                    ret, frame = cap.retrieve()

                    if ret and frame is not None:
                        if (frame.shape[1], frame.shape[0]) != (actual_width, actual_height):
                            frame = cv2.resize(frame, (actual_width, actual_height))

                        # Store the actual timestamp when frame was captured
                        # This is relative to shared_start_time, making synchronization easy
                        capture_timestamp = current_time - start_time
                        self.camera_data[cam_idx]['frame_timestamps'].append(capture_timestamp)

                        # Write frame to disk (this may stall)
                        out.write(frame)
                        recorded_count += 1

                        write_elapsed = time.time() - write_start
                        frame_write_times.append(write_elapsed)

                        if write_elapsed > STALL_THRESHOLD:
                            stall_count += 1
                            print(f"⚠ Camera {cam_idx}: SEVERE DISK STALL! Frame took {write_elapsed * 1000:.0f}ms")

                        next_capture_time += target_interval
                    else:
                        dropped_frames += 1
                        next_capture_time += target_interval

                # Status update
                if current_time - last_status_time >= 10.0:
                    elapsed = current_time - start_time
                    current_fps = recorded_count / elapsed if elapsed > 0 else 0
                    avg_write_time = np.mean(frame_write_times[-300:]) if frame_write_times else 0
                    max_write_time = np.max(frame_write_times[-300:]) if frame_write_times else 0
                    print(f"Camera {cam_idx}: {recorded_count} frames, {elapsed:.1f}s, "
                          f"{current_fps:.1f} FPS, {dropped_frames} dropped, {stall_count} stalls, "
                          f"avg write: {avg_write_time * 1000:.1f}ms, max: {max_write_time * 1000:.1f}ms")
                    last_status_time = current_time

                # Small sleep to prevent busy-waiting
                time.sleep(0.001)

            # Stop the grabber thread
            grabber_stop.set()
            grabber_thread.join(timeout=2.0)

            out.release()

            self.camera_data[cam_idx]['dropped_frames'] = dropped_frames
            self.camera_data[cam_idx]['stall_count'] = stall_count

            actual_duration = time.time() - start_time
            actual_fps = recorded_count / actual_duration if actual_duration > 0 else 0
            avg_write_time = np.mean(frame_write_times) if frame_write_times else 0
            max_write_time = np.max(frame_write_times) if frame_write_times else 0

            # Store actual FPS for later reference
            self.camera_data[cam_idx]['actual_fps'] = actual_fps

            print(f"\n=== Camera {cam_idx} Recording Complete ===")
            print(f"Video saved to: {video_filename}")
            print(f"Total frames recorded: {recorded_count}")
            print(f"Dropped frames: {dropped_frames}")
            print(f"Disk stalls: {stall_count}")
            print(f"Duration: {actual_duration:.1f}s (target: {duration}s)")
            print(f"Average FPS: {actual_fps:.1f}")
            print(f"Avg write time: {avg_write_time * 1000:.1f}ms, Max: {max_write_time * 1000:.1f}ms")

        except Exception as e:
            print(f"✗ Error during camera {cam_idx} recording: {e}")
            import traceback
            traceback.print_exc()

    def create_recording_threads(self, duration, ready_event, start_signal_event):
        """Create and start recording threads for all cameras"""
        threads = []

        for cam_idx in self.caps.keys():
            thread = threading.Thread(
                target=self.record_camera,
                args=(cam_idx, duration, ready_event, start_signal_event)
            )
            thread.daemon = True
            thread.start()
            threads.append(thread)

        ready_event.set()

        return threads

    def cleanup(self):
        """Clean up all camera resources"""
        print("Cleaning up camera resources...")
        try:
            # Stop all grabber threads first
            for cam_idx, stop_event in self.grabber_stop_events.items():
                stop_event.set()

            time.sleep(0.5)  # Give grabber threads time to stop

            # Release video writers
            for cam_idx in list(self.outs.keys()):
                if cam_idx in self.outs:
                    self.outs[cam_idx].release()

            # Release camera captures
            for cam_idx in list(self.caps.keys()):
                if cam_idx in self.caps:
                    self.caps[cam_idx].release()

            cv2.destroyAllWindows()

            self.caps.clear()
            self.outs.clear()
            self.grabber_stop_events.clear()

        except Exception as e:
            print(f"✗ Error during cleanup: {e}")

        print("✓ Camera cleanup complete")


if __name__ == "__main__":
    ports = [
        '/dev/cu.usbmodem180332101',
        '/dev/cu.usbmodem180345701',
        '/dev/cu.usbmodem180337901',
        '/dev/cu.usbmodem180439201'
    ]

    # Initialize tactile recorder
    recorder = TactileDataRecorder(ports)

    # Initialize multi-camera recorder with your three cameras
    video_recorder = MultiCameraRecorder(
        camera_indices=[0, 1],  # Your three external cameras
        width=1920,
        height=1080,
        fps=30.0,
        show_preview=False
    )

    try:
        filename = recorder.start_recording(
            duration=90,
            M_value=200,
            threshold=700,
            digipot=100,
            video_recorder=video_recorder
        )

        if filename is None:
            print("Recording was cancelled or failed")

    except KeyboardInterrupt:
        print("\n⚠ Recording interrupted")
    except Exception as e:
        print(f"\n✗ Error during recording: {e}")
        import traceback

        traceback.print_exc()
    finally:
        recorder.cleanup()
        video_recorder.cleanup()