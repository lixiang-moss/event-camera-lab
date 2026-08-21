# 一、单目 DAVIS346 标定

准备普通黑白棋盘格，并确定：

```text
横向内角点数
纵向内角点数
方格实际边长，单位米
```

以下示例使用 `8×6` 内角点、30 mm 方格，请按实际标定板修改。

### 终端 1：启动标定容器和相机

```bash
cd /home/lx/ec_xiangli

./scripts/check_usb.sh
xhost +local:docker

docker compose run --rm \
  --name event-camera-calibration \
  --user root \
  event-camera-ros bash
```

进入容器后运行：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash

roslaunch event_camera_lab_bringup \
  current_live_stream.launch \
  aps_enabled:=true
```

保持终端 1 运行。

### 终端 2：打开标定程序

Host 上执行：

```bash
docker exec -it event-camera-calibration bash
```

进入容器后：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash

rospack find camera_calibration
rostopic hz /dvs/image_raw
```

看到 APS 图像有频率后按 `Ctrl+C`，检查分辨率：

```bash
rostopic echo -n 1 --noarr /dvs/image_raw
```

应看到：

```text
width: 346
height: 260
```

启动标定 GUI：

```bash
BOARD_COLS=8
BOARD_ROWS=6
SQUARE_SIZE_M=0.030

rosrun camera_calibration cameracalibrator.py \
  --size "${BOARD_COLS}x${BOARD_ROWS}" \
  --square "${SQUARE_SIZE_M}" \
  image:=/dvs/image_raw \
  camera:=/dvs
```

在 GUI 中：

1. 将棋盘格移动到画面中心、边缘和四角。
2. 改变远近、大小和倾斜角度。
3. 等覆盖指标逐渐变绿。
4. 点击 `CALIBRATE`。
5. 等待计算完成。
6. 点击 `SAVE`。
7. 点击 `COMMIT`。

### 验证标定结果

不要先停止 driver，在终端 2 执行：

```bash
ls -lah /root/.ros/camera_info
rostopic echo -n 1 /dvs/camera_info
```

当前这台相机预计生成：

```text
DAVIS-00000890.yaml
```

Host 上检查：

```bash
cd /home/lx/ec_xiangli
ls -lah config/camera_info
```

确认 YAML 存在后：

1. 关闭标定 GUI。
2. 在终端 1 按 `Ctrl+C`。
3. 输入 `exit`。

以后正常启动时会自动加载该 YAML。




## 四、回放并查看 rosbag 画面

先在实时 driver 终端按 `Ctrl+C`，避免实时数据和 bag 使用相同 topic。

终端 1：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm event-camera-ros roscore
```

终端 2：

```bash
cd /home/lx/ec_xiangli

LATEST_BAG="$(basename "$(ls -1t data/davis_mono_*.bag | head -n 1)")"

docker compose run --rm event-camera-ros \
  rosbag play --clock --pause "/workspace/data/${LATEST_BAG}"
```

先保持暂停。

终端 3：

```bash
cd /home/lx/ec_xiangli
xhost +local:docker

docker compose run --rm --user root event-camera-ros \
  roslaunch dvs_renderer renderer_mono.launch
```

renderer 和窗口打开后，回到终端 2 按空格开始播放。此时可以看到 bag 中记录的事件画面。






















# 单目 DAVIS346 rosbag 流程

## 1. Host 终端 1：打开容器

```bash
cd /home/lx/ec_xiangli

./scripts/check_usb.sh
xhost +local:docker

docker compose run --rm \
  --name event-camera-rosbag \
  --user root \
  event-camera-ros bash
```

进入容器后加载环境：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
```

启动单目 DAVIS346：

```bash
roslaunch event_camera_lab_bringup \
  current_live_stream.launch \
  aps_enabled:=true
```

保持终端 1 运行。它现在负责：

- ROS master
- DAVIS driver
- `/dvs/events`
- `/dvs/imu`
- `/dvs/camera_info`
- `/dvs/image_raw`

如果已经完成标定，启动日志应显示成功加载对应的 `DAVIS-XXXXXXXX.yaml`。

## 2. Host 终端 2：进入同一个容器

```bash
docker exec -it event-camera-rosbag bash
```

进入后：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
```

检查 topics：

```bash
rostopic list | sort
```

检查事件频率：

```bash
rostopic hz /dvs/events
```

看到频率后按 `Ctrl+C`。

检查 APS 图像频率：

```bash
rostopic hz /dvs/image_raw
```

看到频率后按 `Ctrl+C`。

检查一帧 APS 信息：

```bash
rostopic echo -n 1 --noarr /dvs/image_raw
```

DAVIS346 应显示：

```text
width: 346
height: 260
```

## 3. 录制 30 秒 rosbag

仍在容器终端 2：

```bash
mkdir -p /workspace/data

BAG_FILE="/workspace/data/davis_mono_$(date +%Y%m%d_%H%M%S).bag"

rosbag record \
  --duration=30 \
  -O "$BAG_FILE" \
  /dvs/events \
  /dvs/imu \
  /dvs/camera_info \
  /dvs/image_raw
```

录制期间在相机前移动具有清晰边缘的物体，或者缓慢移动相机。

等待命令自动结束。不要在录制过程中直接关闭终端，否则可能留下 `.bag.active` 文件。

显示生成的文件名：

```bash
echo "$BAG_FILE"
ls -lh "$BAG_FILE"
```

由于 `/workspace` 对应 Host 项目目录，文件同时保存在：

```text
/home/lx/ec_xiangli/data/
```

## 4. 查看 rosbag 信息

仍在容器终端 2：

```bash
rosbag info "$BAG_FILE"
```

重点检查：

```text
duration
messages
/dvs/events
/dvs/imu
/dvs/camera_info
/dvs/image_raw
```

期望消息类型：

```text
/dvs/events       dvs_msgs/EventArray
/dvs/imu          sensor_msgs/Imu
/dvs/camera_info  sensor_msgs/CameraInfo
/dvs/image_raw    sensor_msgs/Image
```

确认 `/dvs/events` 和 `/dvs/image_raw` 的消息数量大于 0。

如果重新打开了终端、`BAG_FILE` 变量已经不存在，可以这样找到最新文件：

```bash
BAG_FILE="$(ls -1t /workspace/data/davis_mono_*.bag | head -n 1)"
echo "$BAG_FILE"
rosbag info "$BAG_FILE"
```

## 5. 停止实时相机

回到容器终端 1，按：

```text
Ctrl+C
```

此时停止 DAVIS driver 和原来的 ROS master，但先不要退出容器。

在终端 1 启动一个只用于回放的 ROS master：

```bash
roscore
```

保持终端 1 运行。

## 6. 容器终端 2：加载并暂停 rosbag

确认最新 bag：

```bash
BAG_FILE="$(ls -1t /workspace/data/davis_mono_*.bag | head -n 1)"
```

暂停加载：

```bash
rosbag play --clock --pause "$BAG_FILE"
```

它会显示等待状态。暂时不要按空格。

## 7. Host 终端 3：打开回放 GUI

进入同一个容器：

```bash
docker exec -it event-camera-rosbag bash
```

加载环境：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
```

启动事件 renderer 和图像窗口：

```bash
roslaunch dvs_renderer renderer_mono.launch
```

窗口打开后，回到终端 2，按空格开始播放 rosbag。

此时应看到录制的事件实时画面。

播放过程中可以在新的容器终端检查：

```bash
rostopic hz /dvs/events
```

或者查看一包事件的基本信息：

```bash
rostopic echo -n 1 --noarr /dvs/events
```

## 8. 全部结束

1. 在播放终端按 `Ctrl+C`。
2. 在 renderer 终端按 `Ctrl+C`，然后 `exit`。
3. 在 roscore 终端按 `Ctrl+C`。
4. 在终端 1 输入：

```bash
exit
```

`event-camera-rosbag` 临时容器会因为 `--rm` 被删除，但以下内容会保留：

```text
/home/lx/ec_xiangli/data/*.bag
/home/lx/ec_xiangli/config/camera_info/*.yaml
```

如果只需要事件数据、不需要 APS 图像，可以录制更小的 bag：

```bash
rosbag record \
  --duration=30 \
  -O "/workspace/data/davis_events_$(date +%Y%m%d_%H%M%S).bag" \
  /dvs/events \
  /dvs/imu \
  /dvs/camera_info
```