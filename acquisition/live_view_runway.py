"""Live 64 x 256 pressure map from the four runway boards (no recording); q quits."""
import serial
import struct
import time
import threading
import numpy as np
import cv2


class RealTimeTactileVisualizer:
    def __init__(self, ports, threshold=500, M_value=2000, digipot=100, layout='square'):
        self.ports = ports
        self.threshold = threshold  # Display/visualization threshold
        self.M_value = M_value  # How many pixels to sample per frame
        self.digipot = digipot  # Digipot setting
        self.board_size = 64
        self.layout = layout

        # Configure layout based on selection
        if layout == 'square':
            self.grid_rows = 2
            self.grid_cols = 2
            # Layout order: [Board 1, Board 2, Board 3, Board 4]
            # Position mapping: top-left, top-right, bottom-left, bottom-right
            self.layout_order = [3, 1, 2, 4]
            self.transforms = {
                1: 'none',  # Board 1: rotate 90° counterclockwise
                2: 'none',  # Board 2: no rotation
                3: 'none',  # Board 3: rotate 180°
                4: 'none'  # Board 4: rotate 270° counterclockwise (= 90° clockwise)
            }
        elif layout == 'runway':
            self.grid_rows = 1
            self.grid_cols = 4
            # Layout order: [Board 4, Board 3, Board 2, Board 1] (left to right)
            self.layout_order = [4, 3, 2, 1]
            # No transformations for runway
            self.transforms = {1: 'none', 2: 'none', 3: 'none', 4: 'none'}
        else:
            raise ValueError(f"Unknown layout: {layout}")

        # Buffer to hold the latest image for each board (1-4)
        # Use -500 to mark unsampled sensors (changed from 0)
        self.board_buffers = {i: np.full((64, 64), -500, dtype=np.int16) for i in range(1, 5)}
        self.buffer_locks = {i: threading.Lock() for i in range(1, 5)}

        # Statistics tracking
        self.board_stats = {i: {'frames': 0, 'last_update': 0, 'errors': 0} for i in range(1, 5)}
        self.stats_lock = threading.Lock()

        self.running = False

    def configure_board(self, ser, port_num):
        """Configure a board with M_value, threshold, and digipot settings"""
        try:
            # Send configuration: M_value threshold digipot
            config_str = f"{self.M_value} {self.threshold} {self.digipot}\n"
            ser.write(config_str.encode())
            print(f"[Port {port_num}] Sent config: {config_str.strip()}")

            # Wait for "OK" response - reduced timeout for real-time performance
            ok_buffer = bytearray()
            start_time = time.time()
            config_ok = False

            while (time.time() - start_time) < 1.0:  # 1 second timeout (reduced from 3)
                if ser.in_waiting > 0:
                    byte = ser.read(1)
                    ok_buffer.append(byte[0])

                    # Check if we have "OK\n" or "OK\r\n"
                    try:
                        text = ok_buffer.decode('utf-8', errors='ignore')
                        if 'OK' in text:
                            print(f"[Port {port_num}] ✓ Configuration confirmed")
                            config_ok = True
                            break
                    except:
                        pass

                    # Keep buffer small
                    if len(ok_buffer) > 100:
                        ok_buffer = ok_buffer[-50:]

            if not config_ok:
                print(f"[Port {port_num}] ⚠ No OK received (continuing anyway)")

            # Minimal delay
            time.sleep(0.1)
            ser.reset_input_buffer()
            print(f"[Port {port_num}] Ready to receive data")
            return True

        except Exception as e:
            print(f"[Port {port_num}] Failed to configure: {e}")
            return False

    def index_to_coords(self, idx):
        """Replicates MATLAB index_to_coords logic"""
        if idx < 2048:
            r = idx // 32
            c = idx % 32
        else:
            r = (idx - 2048) // 32
            c = (idx - 2048) % 32 + 32
        return r, c

    def apply_transform(self, img, transform_type):
        """Apply rotation transformation to board image"""
        if transform_type == 'rot90':
            return np.rot90(img, k=1)  # 90° counterclockwise
        elif transform_type == 'rot180':
            return np.rot90(img, k=2)  # 180°
        elif transform_type == 'rot270':
            return np.rot90(img, k=3)  # 270° counterclockwise
        elif transform_type == 'none':
            return img
        else:
            return img

    def serial_worker(self, port, board_num):
        """Thread worker to read serial data and update the board buffer"""
        SYNC_MARKER = 0xDEADBEEF
        ser = None

        try:
            print(f"[Port {board_num}] Attempting to connect to {port}...")
            ser = serial.Serial(port, 115200, timeout=2.0)  # Longer timeout for config

            # Try to set larger buffer
            try:
                ser.set_buffer_size(rx_size=100000, tx_size=100000)
            except:
                pass

            print(f"[Port {board_num}] Connected on {port}")

            # Configure the board using the dedicated function
            if not self.configure_board(ser, board_num):
                print(f"[Port {board_num}] Configuration failed, exiting thread")
                return

            # Reduce timeout for real-time data streaming
            ser.timeout = 0.01  # 10ms timeout for fast real-time performance

            frame_count = 0
            error_count = 0
            last_status = time.time()

            while self.running:
                try:
                    sync_data = ser.read(4)
                    if len(sync_data) != 4:
                        continue

                    sync = struct.unpack('<I', sync_data)[0]
                    if sync != SYNC_MARKER:
                        ser.reset_input_buffer()
                        continue

                    header = ser.read(6)
                    if len(header) != 6:
                        ser.reset_input_buffer()
                        continue

                    board_id, count, frame_num = struct.unpack('<HHH', header)

                    if count > 0:
                        pixel_data = ser.read(count * 4)
                        if len(pixel_data) == count * 4:
                            raw_array = np.frombuffer(pixel_data, dtype='<H')
                            indices = raw_array[0::2]
                            values = raw_array[1::2]

                            # Use the board_id from the packet, not the port number!
                            actual_board = board_id

                            # Validate board_id is in valid range
                            if actual_board < 1 or actual_board > 4:
                                print(f"[Port {board_num}] Invalid board_id={actual_board}, skipping")
                                continue

                            # Create FRESH frame initialized to -500 (like MATLAB's -1000)
                            # This matches MATLAB behavior - each frame starts clean
                            fresh_img = np.full((64, 64), -500, dtype=np.int16)

                            for idx, val in zip(indices, values):
                                # Skip invalid indices (like 65535 which is 0xFFFF)
                                if idx >= 4096 or idx == 65535:
                                    continue

                                r, c = self.index_to_coords(idx)
                                # Safety check for bounds
                                if 0 <= r < 64 and 0 <= c < 64:
                                    # Just store the raw value from the board
                                    fresh_img[r, c] = val

                            # Replace entire buffer with fresh frame (thread-safe)
                            with self.buffer_locks[actual_board]:
                                self.board_buffers[actual_board] = fresh_img

                            # Update stats for the actual board
                            with self.stats_lock:
                                self.board_stats[actual_board]['frames'] += 1
                                self.board_stats[actual_board]['last_update'] = time.time()

                            frame_count += 1
                        else:
                            ser.reset_input_buffer()

                    # Periodic status update
                    if time.time() - last_status > 5.0:
                        print(f"[Port {board_num}] Frames received: {frame_count}, Errors: {error_count}")
                        last_status = time.time()

                except serial.SerialException as e:
                    error_count += 1
                    print(f"[Port {board_num}] Serial error: {e}")
                    time.sleep(0.1)
                except Exception as e:
                    error_count += 1
                    print(f"[Port {board_num}] Error: {e}")

        except Exception as e:
            print(f"[Port {board_num}] FATAL ERROR: {e}")
        finally:
            if ser is not None and ser.is_open:
                try:
                    ser.close()
                    print(f"[Port {board_num}] Connection closed")
                except:
                    pass

    def start(self):
        self.running = True
        threads = []

        # Start a thread for each port
        for i, port in enumerate(self.ports):
            board_num = i + 1  # Board numbers are 1-indexed
            t = threading.Thread(target=self.serial_worker, args=(port, board_num))
            t.daemon = True
            t.start()
            threads.append((t, board_num))
            time.sleep(0.5)  # Stagger the starts slightly

        print(f"\n{'=' * 60}")
        print(f"Starting Real-time Display ({self.layout} layout)")
        print(f"Press 'q' to exit")
        print(f"{'=' * 60}\n")

        last_stats_print = time.time()

        while self.running:
            # 1. Stitch boards together based on layout
            combined = np.full((self.board_size * self.grid_rows,
                                self.board_size * self.grid_cols), -500, dtype=np.int16)

            for pos, board_id in enumerate(self.layout_order):
                # Calculate grid position
                grid_row = pos // self.grid_cols
                grid_col = pos % self.grid_cols

                # Calculate pixel positions
                row_start = grid_row * self.board_size
                row_end = (grid_row + 1) * self.board_size
                col_start = grid_col * self.board_size
                col_end = (grid_col + 1) * self.board_size

                # Place the board image (with thread safety)
                # Use copy() to minimize lock time
                with self.buffer_locks[board_id]:
                    combined[row_start:row_end, col_start:col_end] = self.board_buffers[board_id].copy()

            # 2. Apply threshold is now handled at data ingestion, not display
            # Just separate unsampled from sampled
            mask_unsampled = (combined == -500)

            # 3. Normalize for display
            # We need to map three distinct ranges:
            # -500 (unsampled) -> 0 (darkest in custom range)
            # 0 (below threshold) -> 50 (low but visible)
            # 1-4095 (actual data) -> 51-255 (full color range)

            display_img = np.zeros_like(combined, dtype=np.uint8)

            # Unsampled sensors -> map to 0 (will be pure black or darkest blue)
            mask_unsampled = (combined == -500)
            display_img[mask_unsampled] = 0

            # Sampled sensors (including those at/below threshold)
            sampled_mask = ~mask_unsampled
            # Map 0-4095 to 51-255 to clearly separate from unsampled
            display_img[sampled_mask] = np.clip((combined[sampled_mask] / 4095.0 * 204 + 51), 51, 255).astype(np.uint8)

            # 4. Apply Colormap (JET: dark blue -> cyan -> yellow -> red)
            color_img = cv2.applyColorMap(display_img, cv2.COLORMAP_JET)

            # Make unsampled sensors BLACK to clearly distinguish from sampled data
            mask_unsampled = (combined == -500)
            color_img[mask_unsampled] = [0, 0, 0]  # Pure black for unsampled

            # 4.5. Add colorbar on the right
            colorbar_width = 60
            colorbar_height = color_img.shape[0]

            # Create colorbar gradient (51-255 for sampled data)
            # Bottom portion will be black for unsampled
            colorbar_gradient = np.zeros(colorbar_height, dtype=np.uint8)

            # Top 90% shows the data range (51-255)
            data_height = int(colorbar_height * 0.9)
            colorbar_gradient[:data_height] = np.linspace(255, 51, data_height, dtype=np.uint8)

            # Bottom 10% stays at 0 (black for unsampled)
            colorbar_gradient[data_height:] = 0

            colorbar_gradient = np.tile(colorbar_gradient.reshape(-1, 1), (1, colorbar_width))
            colorbar_colored = cv2.applyColorMap(colorbar_gradient, cv2.COLORMAP_JET)

            # Make the unsampled portion pure black
            colorbar_colored[data_height:, :] = [0, 0, 0]

            # Add text labels to colorbar (for the data portion)
            max_value = 4095
            num_labels = 5
            for i in range(num_labels):
                # Calculate position and value (only in data portion)
                y_pos = int((i / (num_labels - 1)) * (data_height - 1))
                value = int(max_value * (1 - i / (num_labels - 1)))

                # Draw label
                label_text = f"{value}"
                cv2.putText(colorbar_colored, label_text, (5, y_pos + 5),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)

            # Add special label for unsampled in the black section
            cv2.putText(colorbar_colored, "N/S", (10, colorbar_height - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2, cv2.LINE_AA)

            # Concatenate main image with colorbar
            color_img = np.hstack([color_img, colorbar_colored])

            # 5. Add status overlay
            current_time = time.time()
            with self.stats_lock:
                for i in range(1, 5):
                    stats = self.board_stats[i]
                    status_text = f"B{i}: {stats['frames']} frames"

                    # Check if board is active (updated in last 2 seconds)
                    time_since_update = current_time - stats['last_update']
                    if stats['frames'] == 0:
                        color = (0, 0, 255)  # Red - no data
                        status_text += " [NO DATA]"
                    elif time_since_update > 2.0:
                        color = (0, 165, 255)  # Orange - stale
                        status_text += " [STALE]"
                    else:
                        color = (0, 255, 0)  # Green - active

                    # Uncomment to show status text on image
                    # y_pos = 20 + (i - 1) * 25
                    # cv2.putText(color_img, status_text, (10, y_pos),
                    #             cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)

            # 6. Show it
            window_name = f'Tactile Real-Time ({self.layout.capitalize()} Layout)'
            cv2.imshow(window_name, color_img)

            # Print stats periodically
            if time.time() - last_stats_print > 10.0:
                print("\n--- Board Status ---")
                with self.stats_lock:
                    for i in range(1, 5):
                        stats = self.board_stats[i]
                        print(f"Board {i}: {stats['frames']} frames, "
                              f"{stats['errors']} errors, "
                              f"last update: {time.time() - stats['last_update']:.1f}s ago")
                last_stats_print = time.time()

            if cv2.waitKey(1) & 0xFF == ord('q'):
                self.running = False
                break

        print("\nStopping threads...")
        for t, board_num in threads:
            t.join(timeout=2.0)

        cv2.destroyAllWindows()
        print("Done!")


if __name__ == "__main__":
    # Use your specific ports
    my_ports = [
        '/dev/cu.usbmodem180332101',
        '/dev/cu.usbmodem180345701',
        '/dev/cu.usbmodem180337901',
        '/dev/cu.usbmodem180439201'
    ]

    viz = RealTimeTactileVisualizer(
        my_ports,
        threshold=700,  # Hardware threshold - board only samples pixels > 500
        M_value=200,  # Sample up to 2000 pixels per frame
        digipot=100,  # Digipot setting
        layout='runway'
    )
    viz.start()