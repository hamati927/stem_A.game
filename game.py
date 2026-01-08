import time
import collections
import argparse
import os
import glob
import cv2
import mediapipe as mp
import enum


class ActionType(enum.Enum):
    """動作の種類"""
    SQUAT = "スクワット"
    STEP_LEFT = "左足踏み"
    STEP_RIGHT = "右足踏み"


class Action:
    """動作指示"""
    def __init__(self, time_s, action_type):
        self.time_s = time_s  # 表示開始時刻
        self.action_type = action_type  # 動作種類
        self.completed = False  # 完了フラグ
        self.deadline = time_s + 3.0  # 3秒以内に完了


class RhythmGame:
    def __init__(self, actions, display_time=3.0, width=800, height=600):
        self.actions = [Action(t, a) for (t, a) in actions]
        self.display_time = display_time
        self.width = width
        self.height = height
        
        # 動作検出用のしきい値
        self.squat_threshold = 0.15  # 腰-膝の距離がこの比率以下になったらスクワット
        self.step_height_threshold = 0.08  # 足首がこの比率以上上がったら足踏み
        
        # 前フレームの状態（動作検出用）
        self.prev_hip_knee_ratio = None
        self.prev_left_ankle_y = None
        self.prev_right_ankle_y = None
        
        # mediapipe import can have slightly different layouts across builds; try a safe fallback
        try:
            self.mp_pose = mp.solutions.pose
            self.mp_drawing = mp.solutions.drawing_utils
        except Exception:
            try:
                from mediapipe import solutions as mps
                self.mp_pose = mps.pose
                self.mp_drawing = mps.drawing_utils
            except Exception as e:
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
                self.mp_drawing = None

    def detect_squat(self, landmarks, h):
        """スクワット検出"""
        try:
            # 左右の腰と膝の平均を取る
            left_hip = landmarks[23]
            right_hip = landmarks[24]
            left_knee = landmarks[25]
            right_knee = landmarks[26]
            
            avg_hip_y = (left_hip.y + right_hip.y) / 2
            avg_knee_y = (left_knee.y + right_knee.y) / 2
            
            # 腰と膝の距離（画面比率）
            hip_knee_ratio = abs(avg_hip_y - avg_knee_y)
            
            # しきい値以下になったらスクワット判定
            if hip_knee_ratio < self.squat_threshold:
                return True
            return False
        except:
            return False
    
    def detect_step_left(self, landmarks, h):
        """左足踏み検出"""
        try:
            left_ankle = landmarks[27]
            left_knee = landmarks[25]
            
            # 足首が膝より上に来たら足踏み
            if left_ankle.y < left_knee.y - self.step_height_threshold:
                return True
            return False
        except:
            return False
    
    def detect_step_right(self, landmarks, h):
        """右足踏み検出"""
        try:
            right_ankle = landmarks[28]
            right_knee = landmarks[26]
            
            # 足首が膝より上に来たら足踏み
            if right_ankle.y < right_knee.y - self.step_height_threshold:
                return True
            return False
        except:
            return False
    
    def draw_action_guide(self, canvas, action_type, x, y):
        """動作の見本を描画"""
        if action_type == ActionType.SQUAT:
            # スクワットの図
            cv2.putText(canvas, 'SQUAT', (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 255), 3)
            # 簡易スティックフィギュア（しゃがんだ姿勢）
            head = (x + 60, y + 40)
            hip = (x + 60, y + 80)
            knee = (x + 60, y + 100)
            cv2.circle(canvas, head, 15, (0, 255, 255), 2)
            cv2.line(canvas, head, hip, (0, 255, 255), 3)
            cv2.line(canvas, hip, knee, (0, 255, 255), 3)
            cv2.line(canvas, hip, (x + 40, y + 100), (0, 255, 255), 3)
            cv2.line(canvas, hip, (x + 80, y + 100), (0, 255, 255), 3)
            
        elif action_type == ActionType.STEP_LEFT:
            cv2.putText(canvas, 'STEP LEFT', (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 0, 255), 3)
            # 左足を上げた姿勢
            head = (x + 60, y + 40)
            hip = (x + 60, y + 80)
            cv2.circle(canvas, head, 15, (255, 0, 255), 2)
            cv2.line(canvas, head, hip, (255, 0, 255), 3)
            cv2.line(canvas, hip, (x + 40, y + 60), (255, 0, 255), 3)  # 左足上げ
            cv2.line(canvas, hip, (x + 80, y + 120), (255, 0, 255), 3)  # 右足
            
        elif action_type == ActionType.STEP_RIGHT:
            cv2.putText(canvas, 'STEP RIGHT', (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 0), 3)
            # 右足を上げた姿勢
            head = (x + 60, y + 40)
            hip = (x + 60, y + 80)
            cv2.circle(canvas, head, 15, (255, 255, 0), 2)
            cv2.line(canvas, head, hip, (255, 255, 0), 3)
            cv2.line(canvas, hip, (x + 40, y + 120), (255, 255, 0), 3)  # 左足
            cv2.line(canvas, hip, (x + 80, y + 60), (255, 255, 0), 3)  # 右足上げ
    def run(self, source=0):
        # source: int for camera index, or string path for video file
        try:
            idx = int(source)
            cap = cv2.VideoCapture(idx)
        except Exception:
            cap = cv2.VideoCapture(source)
        if not cap.isOpened():
            print('カメラ／ビデオを開けません。デバイスやパスを確認してください。')
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

            # 骨格を描画
            if results.pose_landmarks and self.mp_drawing:
                self.mp_drawing.draw_landmarks(canvas, results.pose_landmarks, self.mp_pose.POSE_CONNECTIONS)

            # アクションの処理
            current_action = None
            for action in self.actions:
                if action.completed:
                    continue
                
                # 表示時刻になったか
                if now < action.time_s:
                    continue
                
                # 期限切れチェック
                if now > action.deadline:
                    action.completed = True
                    removed.append(action)
                    print(f'失敗: {action.action_type.value} （時間切れ）')
                    continue
                
                # 現在のアクション
                current_action = action
                
                # 見本を描画
                remaining = action.deadline - now
                self.draw_action_guide(canvas, action.action_type, 50, 100)
                cv2.putText(canvas, f'残り: {remaining:.1f}秒', (50, 200), 
                           cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
                
                # 動作検出
                if results.pose_landmarks:
                    lm = results.pose_landmarks.landmark
                    h, w, _ = canvas.shape
                    
                    detected = False
                    if action.action_type == ActionType.SQUAT:
                        detected = self.detect_squat(lm, h)
                    elif action.action_type == ActionType.STEP_LEFT:
                        detected = self.detect_step_left(lm, h)
                    elif action.action_type == ActionType.STEP_RIGHT:
                        detected = self.detect_step_right(lm, h)
                    
                    if detected:
                        action.completed = True
                        scored += 1
                        removed.append(action)
                        print(f'成功: {action.action_type.value}')
                        # 成功エフェクト
                        cv2.putText(canvas, 'SUCCESS!', (self.width // 2 - 100, self.height // 2), 
                                   cv2.FONT_HERSHEY_SIMPLEX, 2.0, (0, 255, 0), 4)
                
                break  # 1度に1つのアクションのみ

            # HUD
            cv2.putText(canvas, f'Score: {scored} / {len(self.actions)}', (10, 30), 
                       cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)

            cv2.imshow('Lower Body Rhythm Game (Press ESC to quit)', canvas)

            key = cv2.waitKey(1) & 0xFF
            if key == 27:  # ESC
                break

            # 全アクション完了チェック
            if all(a.completed for a in self.actions):
                cv2.putText(canvas, f'Finished! Score: {scored}/{len(self.actions)}', 
                           (100, 300), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 0), 3)
                cv2.imshow('Lower Body Rhythm Game (Press ESC to quit)', canvas)
                cv2.waitKey(3000)
                break

        pose.close()
        cap.release()
        cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description='Lower body exercise rhythm game with pose detection')
    parser.add_argument('--source', '-s', default='0',
                        help='Video source: camera index (0,1,...) or path to video file')
    args = parser.parse_args()

    # アクション譜面: (時刻, 動作種類)
    actions = [
        (2.0, ActionType.SQUAT),
        (6.0, ActionType.STEP_LEFT),
        (10.0, ActionType.STEP_RIGHT),
        (14.0, ActionType.SQUAT),
        (18.0, ActionType.STEP_LEFT),
        (22.0, ActionType.SQUAT),
        (26.0, ActionType.STEP_RIGHT),
        (30.0, ActionType.SQUAT),
    ]
    
    game = RhythmGame(actions)
    game.run(args.source)


if __name__ == '__main__':
    main()
