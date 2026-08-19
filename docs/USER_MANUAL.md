# event-camera-lab 使用手册

## 1. 项目目标

`event-camera-lab` 是一个面向多型号事件相机的 Docker + ROS 实验工程。

当前第一阶段不是做完整算法实验，而是先把一条稳定链路跑通：

```text
事件相机
  -> Host Ubuntu
  -> Docker Ubuntu 20.04
  -> ROS Noetic
  -> ROS driver
  -> ROS topics
  -> event stream / rosbag
```

当前硬件验证使用老师给的相机和 `uzh-rpg/rpg_dvs_ros` 项目。项目命名、容器命名、目录结构都保持中性，是为了后续加入其他事件相机型号。

## 2. 当前技术选择

- Host：Ubuntu 26.04
- Container：Ubuntu 20.04
- ROS：ROS Noetic
- Docker image：`event-camera-lab:noetic`
- Compose service：`event-camera-ros`
- ROS workspace：`ros_ws`
- 当前上游驱动源码：`ros_ws/src/rpg_dvs_ros`
- Prophesee 环境：OpenEB 4.6.2 + `prophesee_ros_wrapper` 4.6.2
- 构建工具：`catkin_tools`
- 相机底层库：`libcaer-dev`，由 iniVation PPA 提供

选择 Docker 的原因是 ROS1 Noetic 和老事件相机驱动更适合 Ubuntu 20.04。宿主系统较新，直接安装旧 ROS 栈容易遇到依赖和系统版本冲突。

## 3. 项目结构

```text
event-camera-lab/
  docker/
    Dockerfile
    entrypoint.sh
  ros_ws/
    src/
      catkin_simple/
      event_camera_lab_bringup/
      event_camera_prophesee_tools/
      prophesee_ros_wrapper/
      rpg_dvs_ros/
  scripts/
    build_image.sh
    build_workspace.sh
    check_topics.sh
    check_usb.sh
    launch_live_stream.sh
    open_shell.sh
    record_events.sh
    record_prophesee_raw.sh
    record_prophesee_rosbag.sh
    replay_prophesee_raw.sh
    convert_prophesee_raw_to_rosbag.sh
  docs/
    SOURCES.md
    USER_MANUAL.md
  data/
  docker-compose.yml
  README.md
```

几个重要原则：

- `ros_ws/src/` 放 ROS 源码包。
- `data/` 放本地采集数据，默认不提交 GitHub。
- `ros_ws/build/`、`ros_ws/devel/`、`ros_ws/logs/` 是构建产物，默认不提交。
- 当前相机相关的真实 ROS 包名，例如 `davis_ros_driver`，只出现在脚本默认 profile 或上游源码中，不作为整个项目命名。

## 4. 从零开始运行

所有命令都在项目根目录执行：

```bash
cd /home/lx/ec_xiangli
```

### 4.1 构建 Docker 镜像

```bash
./scripts/build_image.sh
```

成功后本地会有镜像：

```text
event-camera-lab:noetic
```

### 4.2 检查 USB 设备

连接事件相机后运行：

```bash
./scripts/check_usb.sh
```

它会分别打印：

- Host 上的 `lsusb`
- Docker 容器里的 `lsusb`

只有容器也能看到设备，ROS driver 才有机会连接硬件。

### 4.3 构建 ROS workspace

```bash
./scripts/build_workspace.sh
```

默认构建这些核心包：

```text
catkin_simple
dvs_msgs
dvs_ros_driver
davis_ros_driver
dvxplorer_ros_driver
dvs_renderer
dvs_file_writer
prophesee_event_msgs
prophesee_ros_driver
event_camera_prophesee_tools
```

如果只想构建一部分，可以覆盖 `PACKAGES`：

```bash
PACKAGES="catkin_simple dvs_msgs davis_ros_driver dvs_renderer" ./scripts/build_workspace.sh
```

### 4.4 进入容器

```bash
./scripts/open_shell.sh
```

进入后可以手动运行：

```bash
source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
rospack find davis_ros_driver
rospack find dvs_renderer
```

### 4.5 启动当前 live stream profile

默认 profile 用于一台事件相机：

```bash
./scripts/launch_live_stream.sh
```

这个脚本会让 driver 容器进程以 root 身份运行，因为当前 USB device node 通常属于 `root:root`，普通容器用户只能看到设备但不能写入设备。构建 workspace、查看 topic、录 bag 仍使用普通容器用户。

默认命令是：

```bash
roslaunch event_camera_lab_bringup current_live_stream.launch
```

该 launch 会自动启动 ROS master。当前 profile 里的 driver 默认发布：

```text
/dvs/events
/dvs/image_raw
/dvs/camera_info
/dvs/imu
```

如果同时连接两台 DAVIS346，可以启动双相机 profile：

```bash
CAMERA_PROFILE=current_davis_dual ./scripts/launch_live_stream.sh
```

双相机 profile 仍然使用同一个 `davis_ros_driver`，只是启动两个节点，并分别放到两个 namespace：

```text
/cam0/events
/cam0/image_raw
/cam0/camera_info
/cam0/imu

/cam1/events
/cam1/image_raw
/cam1/camera_info
/cam1/imu
```

当前双相机 profile 不指定 serial number，让 driver 自动连接可用设备。这样使用最简单，但要注意：`/cam0` 和 `/cam1` 对应哪一台物理相机不保证固定。重启、重新插拔 USB、启动顺序变化后，两台相机可能互换 namespace。如果后续实验需要严格区分左/右相机或固定标定关系，再改成 serial number 绑定。

这里的 `current_davis_dual` 是纯驱动 profile，适合无界面采集、远程运行或只使用命令行检查 topic。需要同时观看两路实时事件画面时，使用第 5 节介绍的 `current_davis_dual_with_renderer`。

### 4.6 启动 DVXplorer

单台 DVXplorer 使用项目自己的纯驱动 profile：

```bash
CAMERA_PROFILE=dvxplorer ./scripts/launch_live_stream.sh
```

该入口调用：

```bash
roslaunch event_camera_lab_bringup dvxplorer_live_stream.launch
```

默认不指定 serial number，由 `dvxplorer_ros_driver` 自动连接可用设备。主要 topics 为：

```text
/dvs/events
/dvs/imu
/dvs/camera_info
```

DVXplorer 没有 DAVIS 的 APS 灰度图像流，因此不会发布 `/dvs/image_raw`。需要实时画面时，使用第 5.2 节的 event renderer GUI profile。

### 4.7 启动 Prophesee EVK4-HD

EVK4 首次使用前安装宿主 udev 规则并重新插拔：

```bash
./scripts/install_prophesee_udev_rules.sh
./scripts/check_usb.sh
```

纯驱动与官方 ROS Viewer profile：

```bash
CAMERA_PROFILE=prophesee_evk4 ./scripts/launch_live_stream.sh
CAMERA_PROFILE=prophesee_evk4_with_renderer ./scripts/launch_live_stream.sh
```

默认保留 `/prophesee/camera/cd_events_buffer` 和 `/prophesee/camera/camera_info`。需要现有 `dvs_msgs` 算法接口时显式开启适配器：

```bash
CAMERA_PROFILE=prophesee_evk4 \
  EXTRA_ARGS="enable_dvs_adapter:=true" \
  ./scripts/launch_live_stream.sh
```

此时增加 `/dvs/events`、`/dvs/camera_info` 和 `/dvs/set_camera_info`。默认事件聚合窗口为 1 ms；`event_delta_t:=0.0001` 可恢复官方 100 us。

EVK4 以 OpenEB RAW 作为原始主档，以 rosbag 作为 ROS 实验派生格式。完整录制、回放、strict 转换和 LED 点阵标定流程见 [PROPHESEE_EVK4_GUIDE.md](PROPHESEE_EVK4_GUIDE.md)。

### 4.8 检查 ROS topics

另开一个终端，在项目根目录运行：

```bash
./scripts/check_topics.sh
```

默认检查：

```text
/dvs/events
```

如果未来其他相机使用不同 topic，可以这样改：

```bash
EVENT_TOPIC=/camera/events ./scripts/check_topics.sh
```

双相机 profile 建议分别检查：

```bash
EVENT_TOPIC=/cam0/events ./scripts/check_topics.sh
EVENT_TOPIC=/cam1/events ./scripts/check_topics.sh
```

### 4.9 录制测试数据

```bash
./scripts/record_events.sh
```

默认录制 30 秒 `/dvs/events` 到 `data/`。

可以覆盖参数：

```bash
DURATION=60 EVENT_TOPIC=/dvs/events BAG_PREFIX=first_test ./scripts/record_events.sh
```

双相机 profile 可以同时录制两个 event topic：

```bash
EVENT_TOPICS="/cam0/events /cam1/events" BAG_PREFIX=dual_test ./scripts/record_events.sh
```

生成的 bag 文件不会提交到 GitHub。

## 5. GUI 使用

默认工程按 CLI 优先设计。需要可视化时，可以用 X11。

在 Host 上允许本地 Docker 访问 X11：

```bash
xhost +local:docker
```

然后启动带 renderer 的 profile：

```bash
CAMERA_PROFILE=current_davis_with_renderer ./scripts/launch_live_stream.sh
```

这个 profile 会调用本项目的 GUI launch：

```bash
roslaunch event_camera_lab_bringup current_live_stream_with_renderer.launch
```

它会打开：

- `rqt_image_view`
- `rqt_reconfigure`
- event renderer

GUI profile 默认设置 `aps_enabled=false`，让 `rqt_image_view` 自动订阅 `/dvs_rendering` 并优先显示红/蓝事件图。这样比显示 DAVIS 的 APS 灰度帧更适合确认事件流是否正常。

如果以后想同时观察 APS 灰度帧，可以把 APS 打开：

```bash
CAMERA_PROFILE=current_davis_with_renderer EXTRA_ARGS="aps_enabled:=true" ./scripts/launch_live_stream.sh
```

### 5.1 双相机实时画面

同时连接两台相机后，启动双目 GUI profile：

```bash
CAMERA_PROFILE=current_davis_dual_with_renderer ./scripts/launch_live_stream.sh
```

该 profile 复用双目基础 launch，并为每一路事件流分别启动 renderer 和图像窗口：

```text
/cam0/events -> /cam0/dvs_renderer -> /cam0/dvs_rendering -> rqt_image_view (cam0 window)
/cam1/events -> /cam1/dvs_renderer -> /cam1/dvs_rendering -> rqt_image_view (cam1 window)
```

两个 `rqt_image_view` 窗口会分别显式选择 `/cam0/dvs_rendering` 和 `/cam1/dvs_rendering`。默认 `aps_enabled=false`、`display_method=red-blue`，用于清楚显示正负事件。如果需要改变渲染方式，可以覆盖 launch 参数：

```bash
CAMERA_PROFILE=current_davis_dual_with_renderer \
  EXTRA_ARGS="display_method:=grayscale" \
  ./scripts/launch_live_stream.sh
```

如果只出现一路画面，先确认两路事件 topic 都有数据：

```bash
EVENT_TOPIC=/cam0/events ./scripts/check_topics.sh
EVENT_TOPIC=/cam1/events ./scripts/check_topics.sh
```

此 GUI profile 同样不指定 serial number，所以两个窗口对应的物理相机在重启或重新插拔后可能互换。它适合当前不要求固定左右相机身份的实验；涉及双目标定时需要重新确认物理对应关系。

### 5.2 DVXplorer 实时画面

确认 Host 已允许 Docker 使用 X11 后运行：

```bash
CAMERA_PROFILE=dvxplorer_with_renderer ./scripts/launch_live_stream.sh
```

该 profile 调用项目自己的 `dvxplorer_live_stream_with_renderer.launch`，运行流程是：

```text
/dvs/events -> dvs_renderer -> /dvs_rendering -> rqt_image_view
```

GUI 会显式选择 `/dvs_rendering`，并同时启动 `rqt_reconfigure`。默认采用红蓝事件显示；可以覆盖渲染方式：

```bash
CAMERA_PROFILE=dvxplorer_with_renderer \
  EXTRA_ARGS="display_method:=grayscale" \
  ./scripts/launch_live_stream.sh
```

DVXplorer 的实时窗口显示事件累积图，不是传统相机帧。静止场景可能接近黑屏，移动相机、在镜头前移动物体或改变光照后应看到事件。

### 5.3 EVK4-HD 实时画面

```bash
xhost +SI:localuser:root
CAMERA_PROFILE=prophesee_evk4_with_renderer ./scripts/launch_live_stream.sh
```

该 profile 使用官方 `prophesee_ros_viewer` 直接显示 `/prophesee/camera/*` 原生事件，不生成 `/dvs_rendering`。需要 ROS 图像 topic 时，开启 `enable_dvs_adapter:=true` 后单独运行 `dvs_renderer`。结束 GUI 后可用 `xhost -SI:localuser:root` 收回授权。

如果窗口已经打开但画面不明显，先在相机前挥手、移动相机，或改变光照。事件相机主要响应亮度变化，静止场景可能看起来接近黑屏。

只想手动打开动态参数调节：

```bash
./scripts/open_shell.sh
rosrun rqt_reconfigure rqt_reconfigure
```

GUI 如果打不开，优先检查：

- Host 是否运行了 `xhost +local:docker`
- `DISPLAY` 是否有值
- 是否通过 `docker-compose.yml` 挂载了 `/tmp/.X11-unix`

## 6. 常见问题

### Host 能看到设备，但 Docker 看不到

检查：

```bash
./scripts/check_usb.sh
```

如果 Host 有设备、Container 没有设备，重点看 `docker-compose.yml`：

```yaml
privileged: true
volumes:
  - /dev/bus/usb:/dev/bus/usb
```

当前 bring-up 阶段使用 `privileged: true` 是为了减少 USB 权限问题。系统稳定后，可以再考虑用更严格的 `devices` 或 udev 规则。

### Docker 能看到设备，但 driver 起不来

先确认 workspace 已构建并 source：

```bash
./scripts/open_shell.sh
source /workspace/ros_ws/devel/setup.bash
rospack find davis_ros_driver
```

再直接运行：

```bash
rosrun davis_ros_driver davis_ros_driver
```

如果日志持续出现找不到设备，检查：

- 相机 USB 线是否稳定
- 是否同时有其他程序占用相机
- 容器是否确实用 `privileged` 启动
- live driver 是否通过 `./scripts/launch_live_stream.sh` 启动；直接手动运行时可能因为非 root 用户没有 USB 写权限而失败
- `libcaer-dev` 是否在镜像中安装成功

### ROS topic 没有数据

启动 driver 后检查：

```bash
./scripts/check_topics.sh
```

如果 topic 存在但 `rostopic hz` 没有频率：

- 确认事件相机前方有亮度变化或运动
- 尝试移动相机或移动场景中的物体
- 用 `rqt_reconfigure` 检查事件流相关参数
- 检查 topic 名是否不是默认 `/dvs/events`

### 编译失败

常见检查顺序：

```bash
./scripts/build_image.sh
./scripts/build_workspace.sh
```

如果是缺 ROS 包，进入容器后运行：

```bash
cd /workspace/ros_ws
rosdep install --from-paths src --ignore-src --rosdistro noetic -y
```

如果是某个可选包失败，可以先只构建核心包：

```bash
PACKAGES="catkin_simple dvs_msgs davis_ros_driver dvs_renderer" ./scripts/build_workspace.sh
```

如果构建结果显示 `All packages succeeded`，但同时有 `CMake Deprecation Warning`，通常是上游老 ROS 包的 CMake 最低版本声明过旧。只要没有 `Failed` 或 `Abandoned`，当前 bring-up 阶段可以继续。

如果 Docker build 阶段提示找不到 `libcaer-dev`，说明 iniVation PPA 没有正确加入。当前 Dockerfile 已按 iniVation 官方 Ubuntu 安装说明加入：

```text
ppa:ubuntu-toolchain-r/test
ppa:inivation-ppa/inivation
```

### GUI 打不开

先确认 Host：

```bash
echo $DISPLAY
xhost +local:docker
```

再确认容器：

```bash
./scripts/open_shell.sh
echo $DISPLAY
```

如果你只需要验证 event stream，不需要 GUI，优先使用默认 `./scripts/launch_live_stream.sh`。

## 7. 未来加入其他事件相机

后续加入新型号相机时，按这个顺序处理：

1. 把新相机 ROS driver 放入 `ros_ws/src/`。
2. 在 `docs/SOURCES.md` 记录来源、commit、导入日期、用途。
3. 新建或选择一个 launch/profile，但不要把相机型号写进项目顶层命名。
4. 统一记录这些信息：
   - 分辨率
   - event topic 名
   - timestamp 类型和单位
   - polarity 表示方式
   - 是否有 frame/IMU
   - driver 参数
   - USB/网络连接方式
5. 采集数据时统一放入 `data/` 或外部数据盘，不直接提交 GitHub。
6. 在实验代码中尽量消费统一后的 topic/rosbag，而不是直接依赖某个相机私有接口。

建议未来逐步形成：

```text
不同事件相机
  -> 各自 driver
  -> 统一 ROS topic / rosbag
  -> 统一预处理
  -> 同一个算法
  -> 统一指标
```

## 8. 当前阶段验收标准

当前阶段真正完成，不是“Docker 装好了”，而是：

```text
相机插入电脑
  -> Host lsusb 可见
  -> Container lsusb 可见
  -> ROS driver 可启动
  -> rostopic list 有 event topic
  -> rostopic hz 有事件频率
  -> rosbag 能录制测试数据
```

完成这条链路后，才进入统一算法测试和多型号事件相机比较阶段。
