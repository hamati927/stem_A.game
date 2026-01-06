import time
import collections
import argparse
import os
import glob
import cv2
import mediapipe as mp


class Note:
    def __init__(self, time_s, lane):
        self.time_s = time_s
        self.lane = lane
        self.hit = False


class RhythmGame:
    def __init__(self, notes, travel_time=3.0, width=800, height=600):
        self.notes = [Note(t, l) for (t, l) in notes]
        self.travel_time = travel_time
        self.width = width
        self.height = height
        self.lanes = 4
        self.lane_w = self.width // self.lanes
        self.hit_line_y = int(self.height * 0.8)
        self.note_size = 40
        self.hit_window_px = 60
        # mediapipe import can have slightly different layouts across builds; try a safe fallback
        try:
            self.mp_pose = mp.solutions.pose
        except Exception:
            try:
                from mediapipe import solutions as mps
                self.mp_pose = mps.pose
            except Exception as e:
                # Fallback: if MediaPipe's legacy 'solutions' API is not available (new 'tasks' package),
                # use a dummy pose detector so the demo can still run (no landmarks obtained).
                print('Warning: mediapipe.solutions not available; running with dummy pose detector. Error:', e)
                class _DummyPose:
                    class Pose:
                        def __init__(self, *args, **kwargs):
                            pass
                        def process(self, img):
                            class R:
                                pose_landmarks = None
                            return R()
                self.mp_pose = _DummyPose

    def lane_center_x(self, lane):
        return lane * self.lane_w + self.lane_w // 2

    def run(self, source=0):
        # source: int for camera index, or string path for video file
        try:
            idx = int(source)
            cap = cv2.VideoCapture(idx)
        except Exception:
            cap = cv2.VideoCapture(source)
        if not cap.isOpened():
            print('カメラ／ビデオを開けません。デバイスやパスを確認してください。')
            # カメラデバイスの候補を表示
            devs = glob.glob('/dev/video*')
            if devs:
                print('検出されたビデオデバイス:', ', '.join(devs))
                print('別のカメラを使う場合はカメラ番号で実行: python3 game.py --source 1')
            else:
                print('警告: /dev/video* が見つかりません。USBカメラが接続されているか確認してください。')
            print('動画ファイルを使う場合: python3 game.py --source path/to/video.mp4')
            return

        pose = self.mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5)
        start_time = time.time()

        scored = 0
        removed = []

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)
            canvas = cv2.resize(frame, (self.width, self.height))
            img_rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)

            results = pose.process(img_rgb)

            now = time.time() - start_time

            # draw lanes
            for i in range(self.lanes):
                x = i * self.lane_w
                cv2.rectangle(canvas, (x, 0), (x + self.lane_w, self.height), (50, 50, 50), 1)

            # draw hit line
            cv2.line(canvas, (0, self.hit_line_y), (self.width, self.hit_line_y), (0, 255, 255), 2)

            # prepare wrist position
            wrist_px = None
            if results.pose_landmarks:
                h, w, _ = canvas.shape
                lm = results.pose_landmarks.landmark
                # right wrist index 16, left wrist 15
                rw = lm[16]
                wrist_px = (int(rw.x * w), int(rw.y * h))
                cv2.circle(canvas, wrist_px, 8, (0, 0, 255), -1)

            # draw and update notes
            for note in self.notes:
                # compute where the note should be: it should reach hit_line at note.time_s
                time_to_hit = note.time_s - now
                # when time_to_hit == travel_time -> y = start_y (-note_size)
                # linear interpolate: y = hit_line_y - (time_to_hit / travel_time) * hit_line_y
                frac = 1.0 - (time_to_hit / self.travel_time)
                y = int(frac * self.hit_line_y)
                x = self.lane_center_x(note.lane)

                if frac < 0:
                    # not yet spawned
                    continue

                if note.hit:
                    continue

                # draw note
                cv2.rectangle(canvas, (x - self.note_size // 2, y - self.note_size // 2),
                              (x + self.note_size // 2, y + self.note_size // 2), (0, 200, 0), -1)

                # check hit
                if wrist_px is not None:
                    wx, wy = wrist_px
                    if abs(y - self.hit_line_y) < self.hit_window_px and abs(wx - x) < (self.lane_w // 2):
                        note.hit = True
                        scored += 1
                        removed.append(note)

                # remove notes that passed
                if y > self.height + 50:
                    note.hit = True
                    removed.append(note)

            # remove hit/expired notes
            for r in removed:
                if r in self.notes:
                    self.notes.remove(r)
            removed.clear()

            # HUD
            cv2.putText(canvas, f'Score: {scored}', (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)

            cv2.imshow('Rhythm (Press ESC to quit)', canvas)

            key = cv2.waitKey(1) & 0xFF
            if key == 27:  # ESC
                break

            # finish when no notes
            if not self.notes:
                cv2.putText(canvas, 'Finished - press ESC', (200, 300), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
                cv2.imshow('Rhythm (Press ESC to quit)', canvas)
                cv2.waitKey(0)
                break

        pose.close()
        cap.release()
        cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description='Skeleton-tracking rhythm game')
    parser.add_argument('--source', '-s', default='0',
                        help='Video source: camera index (0,1,...) or path to video file')
    args = parser.parse_args()

    # simple note chart: (time_in_seconds, lane_index)
    notes = [(2.0 + i * 0.8, i % 4) for i in range(12)]
    game = RhythmGame(notes)
    game.run(args.source)


if __name__ == '__main__':
    main()
