# DAVIS346 单目标定与单/双目 rosbag 操作指南

本文适用于 `event-camera-lab` 当前的 Ubuntu 20.04 + ROS Noetic Docker 环境，内容包括：

- DAVIS346 单目内参标定（推荐：APS 灰度图 + 普通棋盘格）
- 标定结果持久化与验证
- 单目 DAVIS346 rosbag 录制、检查和离线回放
- 双目 DAVIS346 rosbag 录制、检查和离线回放

所有命令默认从项目根目录执行：

```bash
cd /home/lx/ec_xiangli
```

本文中的依赖和命令已在 2026-08-16 使用一台 DAVIS346 做过短时验证：APS 图像、标准标定 GUI、rosbag 录制、检查、暂停回放、事件 renderer 和 rqt 窗口均能启动。验证没有采集标定样本，也没有执行 `CALIBRATE`、`SAVE` 或 `COMMIT`。

## 1. 先理解三种数据

DAVIS346 同时提供事件、APS 灰度图和 IMU：

```text
/dvs/events       原始事件，类型为 dvs_msgs/EventArray
/dvs/image_raw    APS 灰度图，类型为 sensor_msgs/Image
/dvs/imu          IMU，类型为 sensor_msgs/Imu
```

单目模式的 `/dvs_rendering`，以及双目模式的 `/cam0/dvs_rendering`、`/cam1/dvs_rendering`，是 `dvs_renderer` 根据事件生成的可视化图像，不是原始事件。事件算法和实验录包应优先保存 `/events`；普通棋盘格标定应使用 APS 的 `/image_raw`。

## 2. 标定板准备

推荐使用平整的黑白棋盘格，并准确记录：

- 横向内角点数 `BOARD_COLS`
- 纵向内角点数 `BOARD_ROWS`
- 相邻方格边长 `SQUARE_SIZE_M`，单位是米

例如一张棋盘格有 8 x 6 个内角点，每个方格边长为 30 mm：

```text
BOARD_COLS=8
BOARD_ROWS=6
SQUARE_SIZE_M=0.030
```

注意：这里填写的是“内角点数量”，不是黑白方格数量。必须用尺子测量实际打印尺寸，不要直接照抄示例值。

标定前应完成：

1. 棋盘格固定在硬质平面上，不能弯曲。
2. 场景光照均匀，避免反光和过曝。
3. 调整 DAVIS346 镜头焦距，使棋盘格边缘清晰。
4. 标定完成后不要再转动镜头，否则内参会失效。

## 3. DAVIS346 单目标定完整流程

### 3.1 检查相机和 X11

在 Host 终端执行：

```bash
cd /home/lx/ec_xiangli
./scripts/check_usb.sh
xhost +local:docker
```

确认 Host 和 Container 的 `lsusb` 输出里都能看到 DAVIS346。

### 3.2 确认持久化标定目录

标定文件默认写入 driver 容器的 `/root/.ros/camera_info`。项目的 `docker-compose.yml` 已将它固定挂载到 Host 的 `config/camera_info/`，因此容器删除后 YAML 仍会保留。首次使用前确认目录存在：

```bash
ls -ld /home/lx/ec_xiangli/config/camera_info
```

实际的 `DAVIS-XXXXXXXX.yaml` 属于设备专属文件，默认被 `.gitignore` 忽略。

### 3.3 启动标定容器和 DAVIS driver

在 Host 终端 1 执行：

```bash
cd /home/lx/ec_xiangli

docker compose run --rm \
  --name event-camera-calibration \
  --user root \
  event-camera-ros bash
```

进入容器后执行：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash

roslaunch event_camera_lab_bringup current_live_stream.launch aps_enabled:=true
```

保持这个终端运行。该命令会启动 ROS master、DAVIS driver，并强制打开 APS 灰度图。

### 3.4 打开第二个容器终端

在 Host 终端 2 执行：

```bash
docker exec -it event-camera-calibration bash
```

标准棋盘格标定程序已经安装在项目镜像中。进入容器后加载环境并确认软件包可用：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
rospack find camera_calibration
rosrun camera_calibration cameracalibrator.py --help
```

如果 `camera_calibration` 找不到，先退出容器并在 Host 重新构建镜像：

```bash
./scripts/build_image.sh
```

### 3.5 检查 APS 图像

在容器终端 2 执行：

```bash
rostopic list | sort
rostopic hz /dvs/image_raw
```

看到持续频率后按 `Ctrl+C` 停止 `rostopic hz`，然后检查一帧消息：

```bash
rostopic echo -n 1 --noarr /dvs/image_raw
```

DAVIS346 正常情况下应显示宽度 346、高度 260。也可以先打开图像窗口检查清晰度和曝光：

```bash
rqt_image_view /dvs/image_raw
```

检查结束后关闭该图像窗口，再进行标定。

### 3.6 启动棋盘格标定 GUI

仍在容器终端 2 中，根据自己的标定板修改以下三个值：

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

GUI 打开后按以下方式采样：

1. 保证整个棋盘格始终在画面中，并能稳定检测到角点。
2. 将棋盘格放在画面中央、四个角、四条边附近。
3. 改变距离，让棋盘格在画面中有大有小。
4. 分别绕水平轴和垂直轴倾斜棋盘格。
5. 缓慢移动，避免运动模糊。
6. 等待 GUI 中位置、尺寸和倾斜覆盖指标变绿。
7. `CALIBRATE` 按钮可用后点击它，并等待计算结束。
8. 检查重投影误差和校正画面，尤其检查画面边缘的直线是否仍然弯曲。
9. 点击 `SAVE` 保存标定采样归档。
10. 点击 `COMMIT`，通过 `/dvs/set_camera_info` 将内参写入 driver 的 camera-info 目录。

计算期间 GUI 短暂无响应属于正常现象，不要强制关闭。

### 3.7 验证标定文件已经保存

标定 GUI 完成 `COMMIT` 后，不要先停止 driver。在容器终端 2 执行：

```bash
ls -lah /root/.ros/camera_info
```

应出现类似文件：

```text
DAVIS-00000889.yaml
```

设备编号会因相机而不同。继续检查 ROS 发布的相机参数：

```bash
rostopic echo -n 1 /dvs/camera_info
```

重点确认：

- `width` 和 `height` 正确
- `D` 不再为空
- `K`、`R`、`P` 不再是全零矩阵

在 Host 终端 3 检查持久化文件：

```bash
cd /home/lx/ec_xiangli
ls -lah config/camera_info
```

只有 Host 的 `config/camera_info/` 中存在 YAML，才说明容器退出后标定结果仍会保留。

### 3.8 结束标定

1. 关闭标定 GUI。
2. 在容器终端 1 中按 `Ctrl+C` 停止 driver。
3. 输入 `exit` 退出容器。

因为使用了 `--rm`，容器会被删除，但 `config/camera_info/` 中的 YAML 会保留。

### 3.9 后续启动时加载标定文件

`docker-compose.yml` 已默认挂载 `config/camera_info/`。完成 `COMMIT` 后，正常启动命令会自动加载与相机设备编号匹配的 YAML：

```bash
cd /home/lx/ec_xiangli
CAMERA_PROFILE=current_davis EXTRA_ARGS="aps_enabled:=true" ./scripts/launch_live_stream.sh
```

启动日志不应再出现对应 `DAVIS-XXXXXXXX.yaml not found` 警告。

## 4. 关于项目自带的事件标定工具

上游还提供：

```bash
roslaunch dvs_calibration davis_intrinsic.launch
```

但该 launch 使用事件流检测规则闪烁的 LED 点阵，默认目标是 5 x 5 LED、点间距 0.05 m、约 500 Hz 闪烁。普通打印棋盘格不能用于这条流程，而且当前 Docker 默认也没有构建 `dvs_calibration` 和 `dvs_calibration_gui`。

对于 DAVIS346，优先使用本文第 3 节的 APS 灰度图棋盘格标定。只有已经具备符合要求的闪烁 LED 标定板时，才考虑上游事件标定流程。

## 5. 单目 DAVIS346 rosbag 测试

### 5.1 启动单目纯驱动

在 Host 终端 1 执行：

```bash
cd /home/lx/ec_xiangli
CAMERA_PROFILE=current_davis EXTRA_ARGS="aps_enabled:=true" ./scripts/launch_live_stream.sh
```

只测试原始事件时可以省略 `EXTRA_ARGS`。录制 APS 图像时必须确保 `aps_enabled:=true`。

### 5.2 检查事件频率

在 Host 终端 2 执行：

```bash
cd /home/lx/ec_xiangli
EVENT_TOPIC=/dvs/events HZ_WINDOW=8 ./scripts/check_topics.sh
```

### 5.3 录制单目 bag

事件、IMU、相机参数和 APS 图像全部录制：

```bash
cd /home/lx/ec_xiangli

DURATION=30 \
BAG_PREFIX=davis_mono \
EVENT_TOPICS="/dvs/events /dvs/imu /dvs/camera_info /dvs/image_raw" \
./scripts/record_events.sh
```

可以始终把 `/dvs/camera_info` 写在录制列表中，但只有相机已经完成 `COMMIT` 或启动时成功加载对应 YAML，driver 才会实际发布该消息。未标定时 topic 名称可能存在，bag 中却不会出现 `camera_info` 记录，这是正常行为。

如果只需要事件实验数据，建议减少文件体积：

```bash
DURATION=30 \
BAG_PREFIX=davis_mono_events \
EVENT_TOPICS="/dvs/events /dvs/imu /dvs/camera_info" \
./scripts/record_events.sh
```

录制期间在相机前移动具有清晰边缘的物体，或缓慢移动相机。事件相机面对完全静止场景时事件数量可能很少。

### 5.4 检查单目 bag

Host 上找到最新 bag：

```bash
cd /home/lx/ec_xiangli
ls -lht data/*.bag
```

将下列文件名替换成实际文件名：

```bash
docker compose run --rm event-camera-ros \
  rosbag info /workspace/data/davis_mono_YYYYMMDD_HHMMSS.bag

docker compose run --rm event-camera-ros \
  rosbag check /workspace/data/davis_mono_YYYYMMDD_HHMMSS.bag
```

首次在临时容器中运行时，`rosbag check` 可能先提示 rosdep view 为空。如果最后仍输出 `Bag file does not need any migrations.` 并以成功状态退出，表示当前 bag 无需迁移且检查已通过；这条提示不影响 `rosbag info`、录制或回放。

重点检查：

- `duration` 接近设定录制时间
- `/dvs/events` 的 message count 大于 0
- 类型为 `dvs_msgs/EventArray`
- `/dvs/imu` 的 message count 大于 0
- 如果启用了 APS，`/dvs/image_raw` 的 message count 大于 0
- 只有已经加载标定 YAML 时，才要求 `/dvs/camera_info` 的 message count 大于 0

### 5.5 离线回放单目 bag

回放前先停止所有 live driver，避免实时相机和 bag 同时发布同名 topic。

Host 终端 1：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm event-camera-ros roscore
```

Host 终端 2：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm event-camera-ros \
  rosbag play --clock --pause /workspace/data/davis_mono_YYYYMMDD_HHMMSS.bag
```

该命令会加载 bag 并暂停。先不要按空格，继续启动下面的 renderer。

Host 终端 3，启动事件 renderer：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm --user root event-camera-ros \
  rosrun dvs_renderer dvs_renderer \
  __name:=bag_renderer \
  _display_method:=red-blue \
  events:=/dvs/events \
  camera_info:=/dvs/camera_info \
  image:=/dvs/image_raw \
  dvs_rendering:=/dvs_rendering
```

Host 终端 4，显式指定图像 topic 打开窗口：

```bash
cd /home/lx/ec_xiangli
xhost +local:docker
docker compose run --rm --user root event-camera-ros \
  rqt_image_view /dvs_rendering
```

这里不直接使用上游 `renderer_mono.launch` 自带的 rqt 节点，因为该窗口在当前环境中不会可靠地预选 `/dvs_rendering`。显式传入 topic 后可确认窗口真正建立订阅。

回到终端 2，按空格开始播放。然后在 Host 终端 5 检查回放事件频率：

```bash
cd /home/lx/ec_xiangli
EVENT_TOPIC=/dvs/events HZ_WINDOW=8 ./scripts/check_topics.sh
```

需要慢速逐段检查时，可将播放命令改为：

```bash
docker compose run --rm event-camera-ros \
  rosbag play --clock --pause -r 0.5 \
  /workspace/data/davis_mono_YYYYMMDD_HHMMSS.bag
```

按空格开始或暂停。

## 6. 双目 DAVIS346 rosbag 测试

### 6.1 启动双目纯驱动

同时插入两台 DAVIS346，在 Host 终端 1 执行：

```bash
cd /home/lx/ec_xiangli
CAMERA_PROFILE=current_davis_dual ./scripts/launch_live_stream.sh
```

当前双目 profile 不绑定 serial number，所以重启或重新插拔后，物理相机与 `/cam0`、`/cam1` 的对应关系可能互换。录制前应遮挡或移动其中一台相机，人工确认左右对应关系并写入实验记录。

### 6.2 检查两路事件流

Host 终端 2：

```bash
EVENT_TOPIC=/cam0/events HZ_WINDOW=8 ./scripts/check_topics.sh
```

Host 终端 3：

```bash
EVENT_TOPIC=/cam1/events HZ_WINDOW=8 ./scripts/check_topics.sh
```

两路都必须有持续频率，不能只看到 topic 名称。

### 6.3 录制双目 bag

在另一个 Host 终端执行：

```bash
cd /home/lx/ec_xiangli

DURATION=30 \
BAG_PREFIX=davis_stereo \
EVENT_TOPICS="/cam0/events /cam1/events /cam0/imu /cam1/imu /cam0/camera_info /cam1/camera_info" \
./scripts/record_events.sh
```

两台相机都需要已有并成功加载各自的标定 YAML，bag 中才会包含两路 `camera_info`。未完成标定时仍可录制事件、IMU 和 APS 图像。

如果实验需要 APS 图像，可增加：

```text
/cam0/image_raw /cam1/image_raw
```

但文件会明显增大。事件立体算法通常首先需要的是两路 `/events`、相机内参以及相机间外参。

### 6.4 检查双目 bag

```bash
cd /home/lx/ec_xiangli
ls -lht data/davis_stereo_*.bag

docker compose run --rm event-camera-ros \
  rosbag info /workspace/data/davis_stereo_YYYYMMDD_HHMMSS.bag

docker compose run --rm event-camera-ros \
  rosbag check /workspace/data/davis_stereo_YYYYMMDD_HHMMSS.bag
```

首次运行时可能出现与单目检查相同的空 rosdep view 提示，以最后的 migration 结论和命令退出状态为准。

必须确认：

- `/cam0/events` 和 `/cam1/events` 都有消息
- 两路消息类型都是 `dvs_msgs/EventArray`
- 两路持续时间接近
- 如果两台相机都已加载标定 YAML，两路 `camera_info` 都被记录
- 需要 IMU 时，两路 `imu` 都有消息

### 6.5 离线回放双目 bag

停止所有 live driver 后启动 ROS master。

Host 终端 1：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm event-camera-ros roscore
```

Host 终端 2：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm event-camera-ros \
  rosbag play --clock --pause /workspace/data/davis_stereo_YYYYMMDD_HHMMSS.bag
```

该命令会等待空格键。先启动下面两路 renderer 和两个图像窗口，再回到终端 2 按空格开始回放。

Host 终端 3，启动 cam0 renderer：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm --user root event-camera-ros \
  rosrun dvs_renderer dvs_renderer \
  __ns:=/cam0 \
  __name:=bag_renderer \
  events:=/cam0/events \
  camera_info:=/cam0/camera_info \
  image:=/cam0/image_raw \
  dvs_rendering:=/cam0/dvs_rendering
```

Host 终端 4，启动 cam1 renderer：

```bash
cd /home/lx/ec_xiangli
docker compose run --rm --user root event-camera-ros \
  rosrun dvs_renderer dvs_renderer \
  __ns:=/cam1 \
  __name:=bag_renderer \
  events:=/cam1/events \
  camera_info:=/cam1/camera_info \
  image:=/cam1/image_raw \
  dvs_rendering:=/cam1/dvs_rendering
```

Host 终端 5，显示 cam0：

```bash
cd /home/lx/ec_xiangli
xhost +local:docker
docker compose run --rm --user root event-camera-ros \
  rqt_image_view /cam0/dvs_rendering
```

Host 终端 6，显示 cam1：

```bash
cd /home/lx/ec_xiangli
xhost +local:docker
docker compose run --rm --user root event-camera-ros \
  rqt_image_view /cam1/dvs_rendering
```

同时检查回放频率：

```bash
EVENT_TOPIC=/cam0/events HZ_WINDOW=8 ./scripts/check_topics.sh
EVENT_TOPIC=/cam1/events HZ_WINDOW=8 ./scripts/check_topics.sh
```

## 7. 常见问题

### `/dvs/image_raw` 没有消息

确认 driver 使用：

```bash
aps_enabled:=true
```

GUI 事件显示 profile 默认可能关闭 APS，以突出事件渲染；这不适合普通棋盘格标定。

### 标定 GUI 识别不到棋盘格

- 检查填写的是内角点数量。
- 检查方格尺寸单位是米。
- 改善光照和焦距。
- 降低运动速度，避免模糊。
- 避免棋盘格出画面或严重反光。

### 点击 COMMIT 后 Host 没有 YAML

项目的 Compose 配置会自动把 Host 的 `config/camera_info/` 挂载到容器的 `/root/.ros/camera_info`，不需要在命令中重复添加 `-v`。先在 Host 确认 Compose 展开的挂载配置：

```bash
docker compose config | grep -A3 camera_info
```

然后分别检查容器内和 Host 目录：

```bash
docker exec event-camera-calibration ls -lah /root/.ros/camera_info
ls -lah /home/lx/ec_xiangli/config/camera_info
```

如果两处都没有 YAML，确认 driver 是以 root 用户运行、`/dvs/set_camera_info` 服务存在，并检查点击 `COMMIT` 后的标定程序与 driver 日志。

### 回放时 topic 有数据但画面不明显

事件相机只响应亮度变化。如果 bag 录制时场景基本静止，事件渲染可能接近黑色。使用 `rosbag info` 确认事件 message count，再检查每个 EventArray 是否包含事件。

### 双目 bag 只有一路事件

录制前分别运行：

```bash
rostopic hz /cam0/events
rostopic hz /cam1/events
```

两路都稳定后再开始录制。仅仅在 `rostopic list` 中看到 topic 不代表相机正在持续发布。

### 播放 bag 时出现重复 publisher 或节点冲突

先停止所有 live driver 和旧的 renderer，再启动 `roscore` 和 `rosbag play`。不要在回放时启动包含硬件 driver 的 live-stream launch。

## 8. 完成检查清单

单目标定完成标准：

- [ ] `/dvs/image_raw` 分辨率为 346 x 260
- [ ] GUI 覆盖了中心、边缘、远近和不同倾角
- [ ] 已完成 `CALIBRATE`、`SAVE`、`COMMIT`
- [ ] Host 的 `config/camera_info/` 中存在 `DAVIS-XXXXXXXX.yaml`
- [ ] `/dvs/camera_info` 中 `D`、`K`、`R`、`P` 有有效数值
- [ ] 使用正常 Compose 启动命令重启后，driver 自动加载 YAML，且不再出现 calibration file not found

rosbag 完成标准：

- [ ] `rosbag info` 显示预期 topic 和消息类型
- [ ] `rosbag check` 未报告需要迁移或 bag 损坏
- [ ] 单目 `/dvs/events` 有持续消息
- [ ] 双目 `/cam0/events` 和 `/cam1/events` 都有持续消息
- [ ] 已加载标定 YAML 时，bag 中包含对应的 `camera_info`
- [ ] 离线回放时 `rostopic hz` 有频率
- [ ] renderer 能从 bag 的事件流生成实时画面
- [ ] 双目实验已记录本次 `/cam0`、`/cam1` 的物理对应关系
