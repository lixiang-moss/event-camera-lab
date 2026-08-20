# Prophesee EVK4-HD 接入与数据指南

## 1. 适用范围

本文说明如何在 `event-camera-lab` 中使用一台 Prophesee EVK4-HD，包括：

- OpenEB 与 ROS 驱动环境
- 原生 ROS topic 和可选 `dvs_msgs` 适配
- 官方 ROS Viewer 实时画面
- OpenEB RAW 原始数据录制
- ROS rosbag 实验数据录制
- RAW 离线回放、转换和完整性检查
- LED 点阵内参标定入口与多格式导出

当前提供 EVK4 单目和双目 profile，并校验 IMX636 `system_ID=49`。单目保留官方 wrapper 的原生 topic；双目使用项目自有统一 `dvs_msgs` 驱动，并以 serial 固定 `/cam0`、`/cam1`。双目真机画面、同步线和同步精度尚未验证。

## 2. 固定版本与兼容边界

工程固定使用：

| 组件 | 版本 | Commit |
| --- | --- | --- |
| OpenEB | `4.6.2` | `53b3618935f90dcc0f64993ccbb79514384404b0` |
| `prophesee_ros_wrapper` | `4.6.2` | `8eba7cecd19f31585032188a5daa5908c848e2c4` |
| Container | Ubuntu 20.04 | Dockerfile 固定 |
| ROS | Noetic | ROS1 |

镜像内 `/opt/metavision/share/openeb-build-info.txt` 记录构建时实际校验过的 OpenEB 根仓库 commit。`metavision_software_info -c` 输出的是该发行版源码内嵌的 SDK commit，不是 OpenEB 根仓库 commit，不能用它代替前者做版本核验。

[OpenEB 4.6.2 README](https://github.com/prophesee-ai/openeb/blob/4.6.2/README.md)明确列出 Ubuntu 20.04/22.04 和 EVK4-HD；[wrapper 4.6.2](https://github.com/prophesee-ai/prophesee_ros_wrapper/tree/4.6.2)列出 EVK4 IMX636、Ubuntu 20.04/22.04 与 ROS Noetic/Melodic。

Prophesee `stable` 在线文档会随最新 SDK 更新。当前兼容表显示 SDK 4.0-4.6 支持 Ubuntu 20.04 和 EVK4-HD，但最新 5.x 已不支持 Ubuntu 20.04。升级 5.x 前必须重新评估基础镜像、ROS wrapper API、插件、设备固件和既有 RAW 的回放兼容性，不能只修改版本号。

本工程不安装 SDK Pro、Metavision Studio 或授权下载组件，也不会自动更新设备固件。若设备检查出现固件不兼容提示，应停止测试并记录完整提示，再人工决定升级方案。

## 3. 工程结构

```text
docker/Dockerfile
  多阶段编译 OpenEB 4.6.2，安装到 /opt/metavision

ros_ws/src/prophesee_ros_wrapper/
  官方 wrapper 4.6.2 普通源码副本，不保留内部 .git，不打补丁

ros_ws/src/event_camera_prophesee_tools/
  项目自有设备检查、消息适配、RAW 录制/检查/回放工具

ros_ws/src/event_camera_lab_bringup/launch/
  项目自有 EVK4 live、GUI 和标定 launch

data/prophesee/raw/
data/prophesee/rosbag/
data/prophesee/manifests/
  本机实验数据，默认不提交 Git

config/camera_info/
  按 serial 保存的 ROS CameraInfo YAML，默认不提交 Git

config/calibration/prophesee/
  OpenCV/Kalibr 导出结果，默认不提交 Git
```

OpenEB 在 Docker 构建时按 tag 克隆完整源码和子模块，并校验 commit。Python bindings 和测试关闭；HAL、Driver、UI、Viewer、文件工具和 Prophesee 插件保留。

## 4. 首次安装

### 4.1 构建镜像和工作区

```bash
cd /home/lx/ec_xiangli
./scripts/build_image.sh
./scripts/build_workspace.sh
```

验证版本和工具：

```bash
./scripts/open_shell.sh
metavision_software_info --version
metavision_software_info --commit
command -v metavision_platform_info
command -v metavision_viewer
command -v metavision_file_info
rospack find prophesee_ros_driver
rospack find event_camera_prophesee_tools
```

`OPENEB_COMMIT` 环境变量记录的是 OpenEB 顶层仓库锁定 commit。`metavision_software_info --commit` 显示的是该工具编译时嵌入的 SDK 模块 commit，两者不要求文本相同。

### 4.2 安装宿主机 udev 规则

USB 设备可被 `lsusb` 看到，不等于普通容器用户可以打开设备。执行：

```bash
./scripts/install_prophesee_udev_rules.sh
```

该命令需要宿主机管理员密码。完成后拔出并重新插入 EVK4，再运行：

```bash
./scripts/check_usb.sh
```

脚本依次检查：

1. Host 与容器的 USB 可见性。
2. `/etc/udev/rules.d/88-cyusb.rules` 是否存在。
3. 当前 USB device node 权限。
4. OpenEB HAL 是否识别为 EVK4-HD/IMX636。

Compose 当前仍保留 `/dev/bus/usb` 映射和 `privileged: true`，以免影响 DAVIS、DVXplorer bring-up。未来收紧容器权限时，需要重新测试所有相机。

## 5. 实时 ROS 模式

### 5.1 纯驱动 profile

```bash
CAMERA_PROFILE=prophesee_evk4 ./scripts/launch_live_stream.sh
```

启动前，项目设备工具按唯一硬件 serial 检查在线 Prophesee 相机。若检测到两个不同 serial，单机 profile 会拒绝继续。用户不需要手工填写 serial；若设置 `CAMERA_SERIAL`，脚本只把它作为预期值，并要求它与检测结果完全相等。

需要特别区分“身份校验”和“驱动级 serial 绑定”：官方 wrapper 4.6.2 的实时 publisher 不读取 serial，而是调用 `Camera::from_first_available()`。因此本工程通过“只允许一个唯一在线 serial”保证它打开的就是已校验设备，再用该 serial 选择标定文件。不要绕过 `launch_live_stream.sh` 直接给 launch 填写任意 `camera_serial`；该 launch 参数本身只是已校验身份的元数据标签。

默认原生接口：

```text
/prophesee/camera/cd_events_buffer  prophesee_event_msgs/EventArray
/prophesee/camera/camera_info       sensor_msgs/CameraInfo
```

官方 wrapper 保持原样。实时相机仍由官方 `prophesee_ros_publisher` 打开。

### 5.2 GUI profile

允许 root 容器进程访问 X11：

```bash
xhost +SI:localuser:root
CAMERA_PROFILE=prophesee_evk4_with_renderer ./scripts/launch_live_stream.sh
```

结束后可收回授权：

```bash
xhost -SI:localuser:root
```

GUI profile 启动官方 `prophesee_ros_viewer`。它直接订阅原生事件并显示画面，不发布 ROS 图像，所以不会出现 `/dvs_rendering`。这与 DAVIS/DVXplorer 使用 `dvs_renderer + rqt_image_view` 的方式不同。

事件相机响应亮度变化。静止场景事件稀少时，移动相机、在镜头前移动物体或改变照明后再判断画面是否正常。

### 5.3 可选 `dvs_msgs` 适配器

适配器默认关闭。需要与现有算法、`dvs_renderer` 或统一录包接口对接时显式开启：

```bash
CAMERA_PROFILE=prophesee_evk4 \
  EXTRA_ARGS="enable_dvs_adapter:=true" \
  ./scripts/launch_live_stream.sh
```

增加以下接口：

```text
/dvs/events             dvs_msgs/EventArray
/dvs/camera_info        sensor_msgs/CameraInfo
/dvs/set_camera_info    sensor_msgs/SetCameraInfo
```

转换仅复制等价字段：`x`、`y`、`polarity`、单事件时间戳、宽度和高度，不做滤波、坐标变换或事件抽样。

默认参数：

```text
camera_name=camera
output_namespace=dvs
frame_id=event_camera_optical_frame
event_delta_t=0.001
camera_info_url=file:///workspace/config/camera_info/prophesee_<serial>.yaml
```

### 5.4 双目 profile

双目必须提供两个不同 serial：

```bash
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk4_dual \
  ./scripts/launch_live_stream.sh

CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk4_dual_with_renderer \
  ./scripts/launch_live_stream.sh
```

双目直接发布 `/cam0/events`、`/cam1/events` 及各自的 CameraInfo、Trigger；GUI 输出 `/cam0/dvs_rendering` 和 `/cam1/dvs_rendering`。默认 `SYNC_MODE=standalone`。只有接好同步线后才可设置 `SYNC_MODE=master_slave`，此时 cam1 为 slave、cam0 为 master。未完成双机实测前，不能声明两路已达到确定的同步精度。

## 6. 事件聚合窗口

本工程默认 `event_delta_t=0.001` 秒，即 1 ms。官方 wrapper 默认值是 100 us。

恢复官方值：

```bash
CAMERA_PROFILE=prophesee_evk4 \
  EXTRA_ARGS="event_delta_t:=0.0001 enable_dvs_adapter:=true" \
  ./scripts/launch_live_stream.sh
```

两种设置的影响：

| 设置 | 消息频率 | 单包事件数 | 延迟 | ROS/CPU 开销 |
| --- | --- | --- | --- | --- |
| 1 ms | 较低 | 较多 | 较高 | 较低 |
| 100 us | 较高 | 较少 | 较低 | 较高 |

聚合窗口不改变每个事件自身的时间戳，但会改变 ROS 消息边界、消息数量、调度压力和 bag 元数据。论文实验必须记录该值，不能把 1 ms 与 100 us 的结果当成完全相同的运行条件。

## 7. 数据原则

EVK4 数据采用两层管理：

- OpenEB RAW 是原始主档，保留设备 header 与 EVT3 编码流。
- ROS rosbag 是派生实验格式，用于 ROS 算法、统一 topic 和可视化。

EVK4 RAW 回放和转换校验 IMX636 `system_ID=49`，型号不匹配时拒绝继续。

目录：

```text
data/prophesee/raw/
data/prophesee/rosbag/
data/prophesee/manifests/
```

这些目录中的数据文件均被 `.gitignore` 排除。每次正式采集后应同时备份数据文件、manifest 和 SHA256，不能只保留 bag 文件名。

## 8. RAW 录制与检查

### 8.1 CLI 录制

```bash
DURATION=60 RAW_PREFIX=experiment01 ./scripts/record_prophesee_raw.sh
```

`DURATION=0` 表示持续录制，按 `Ctrl+C` 正常结束。项目 C++ 工具调用 OpenEB `Camera::start_recording()` / `stop_recording()`，退出前关闭 RAW。

CLI recorder 默认使用 OpenEB 相机设置，manifest 记录 `camera_settings_policy=openeb_defaults`；传入 bias 文件时记录 `openeb_defaults_with_bias_override` 及输入文件哈希。若实验需要固定 ROI 或 ERC，须扩展 CLI recorder 并把设置写入 manifest，不能只凭口头记录参数。

生成：

```text
data/prophesee/raw/experiment01_<serial>_<UTC>.raw
data/prophesee/manifests/experiment01_<serial>_<UTC>.raw.yaml
```

检查文件：

```bash
./scripts/open_shell.sh
metavision_file_info -i /workspace/data/prophesee/raw/example.raw
rosrun event_camera_prophesee_tools prophesee_raw_info \
  /workspace/data/prophesee/raw/example.raw
```

### 8.2 Metavision Viewer 录制

```bash
xhost +SI:localuser:root
RAW_PREFIX=viewer01 ./scripts/record_prophesee_raw_with_viewer.sh
```

可加载固定相机设置：

```bash
CAMERA_SETTINGS=/home/lx/ec_xiangli/config/prophesee/experiment01.json \
RAW_PREFIX=viewer01 ./scripts/record_prophesee_raw_with_viewer.sh
```

在 Viewer 中按空格开始录制，再按空格停止。若在 GUI 中调整了 bias、ROI 或 ERC，退出前按 `s` 保存实际设置，再按 `q` 退出。脚本记录输入/保存设置、RAW bias sidecar 的路径与 SHA256，以及 CD event/trigger 数；若 `saved_camera_settings_sha256` 为 `none`，不能声称 GUI 调整后的参数已被完整归档。只有实际生成非空 RAW 后脚本才写 manifest。

官方参考：

- [Events Recording](https://docs.prophesee.ai/stable/guides/events_recording.html)
- [Metavision Viewer](https://docs.prophesee.ai/stable/samples/modules/stream/viewer.html)
- [RAW File Format](https://docs.prophesee.ai/stable/data/file_formats/raw.html)

`stable` 页面可能对应比 4.6.2 更新的 SDK；具体命令行为以本工程锁定的 OpenEB 4.6.2 二进制和本手册实测为准。

### 8.3 双目 RAW

```bash
CAMERA_PROFILE=prophesee_evk4_dual \
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
DURATION=60 ./scripts/record_prophesee_raw.sh
```

命令生成两份 RAW 和一个 pair manifest。成对回放与转换使用 `replay_prophesee_raw_pair.sh` 和 `convert_prophesee_raw_pair_to_rosbag.sh`；两路采用同一 ROS epoch，并保留源 RAW 时间戳之间的偏移。转换分别录制临时 bag，再按首事件或 header 时间戳归并最终 bag。`strict` 分别检查两路 CD event 和 trigger 数量。

## 9. 实时 rosbag

终端 A 启动适配器：

```bash
CAMERA_PROFILE=prophesee_evk4 \
  EXTRA_ARGS="enable_dvs_adapter:=true" \
  ./scripts/launch_live_stream.sh
```

终端 B 录包：

```bash
DURATION=60 BAG_PREFIX=experiment01 \
  ./scripts/record_prophesee_rosbag.sh
```

默认只保存：

```text
/dvs/events
/dvs/camera_info
```

原生 `/prophesee/camera/cd_events_buffer` 不重复写入 bag。RAW 才是原始主档；实时 bag 不能代替同一实验的 RAW 归档。

脚本自动执行 `rosbag info` 和 `rosbag check`，并记录事件数、消息数、分辨率、时间区间、serial、版本、参数、bias/标定 SHA256 和 bag SHA256。

`event_delta_t_s`、同步角色和 bias 路径直接读取正在运行的节点。可用 `EVENT_DELTA_T=0.001` 或 `SYNC_MODE=master_slave` 作为断言；如果断言值与 driver 实际参数不一致，录包会拒绝开始，而不会把猜测值写进 manifest。

## 10. RAW 离线回放

回放为 ROS topic：

```bash
RAW_FILE=/workspace/data/prophesee/raw/example.raw \
  ./scripts/replay_prophesee_raw.sh
```

默认行为：

- 按 RAW 原始相对时间 1.0x 发布。
- 默认开启 `dvs_msgs` 适配器。
- 自动在文件结束后退出。
- 每个事件时间戳映射为 `ROS 启动时刻 + RAW 相对微秒时间`。

该映射保留事件间隔，不保留采集时的绝对墙钟时间。论文中应写成“相对时间保持并平移到回放时 ROS 时间基准”，不能声称恢复了原始绝对采集时刻。

只要原生 topic：

```bash
RAW_FILE=/workspace/data/prophesee/raw/example.raw \
ENABLE_DVS_ADAPTER=false ./scripts/replay_prophesee_raw.sh
```

带官方 ROS Viewer：

```bash
RAW_FILE=/workspace/data/prophesee/raw/example.raw \
WITH_VIEWER=true ./scripts/replay_prophesee_raw.sh
```

项目使用自有 `prophesee_raw_publisher` 完成离线发布。原因是 wrapper 4.6.2 的示例 publisher 在 RAW 模式先启动 Camera、后注册事件回调，短文件可能在订阅就绪前播完。项目节点在启动前注册回调并等待订阅者，EOF 时刷新不足 1 ms 的尾批次；官方 wrapper 源码没有被修改。

## 11. RAW 转 rosbag

```bash
RAW_FILE=/workspace/data/prophesee/raw/example.raw \
INTEGRITY_MODE=strict \
  ./scripts/convert_prophesee_raw_to_rosbag.sh
```

自动流程：

1. 完整解码 RAW 并统计 CD 事件。
2. 启动 ROS master 和适配器。
3. 先启动 rosbag，并确认它已订阅 `/dvs/events`。
4. 再以 1.0x 启动 RAW publisher。
5. 等待 publisher 自然到达 EOF，并检查退出状态；按 RAW 时长设置独立 watchdog。
6. 正常结束 rosbag。
7. 执行 `rosbag info`、`rosbag check`、事件计数和 SHA256。
8. 写入转换 manifest。

完整性模式：

- `strict`：RAW 与 bag 的事件总数必须完全相等，默认使用。
- `relaxed`：仅允许事件数差异比例不超过 `0.1%`。publisher 超时、崩溃或 RAW 解码错误在两种模式下都直接失败。

EVT3 RAW 是连续事件流，没有可供本项目校验的文件尾标记。一个在事件边界处被截短的文件仍可能被 OpenEB 当作较短的有效流解码，因此 `strict` 只证明“当前源 RAW 中可解码的事件全部进入了 bag”。归档和论文复核时还应保存采集 manifest 与源 RAW SHA256，并核对预期录制时长、文件大小和结束方式；SHA256 可发现归档后的变化，但不能反推采集时是否提前结束。

论文表述边界：

- strict 通过后，只能表述“RAW 与 bag 的 CD 事件总数一致”；消息会重新分包，时间戳会整体平移，而且总数检查本身不证明逐字段等价。
- relaxed 通过后，只能披露“事件数差异不超过 0.1%”，不能声称逐事件等价。
- 两种模式都不能仅凭总数证明事件顺序、字段和时间戳绝对正确；正式数据还应抽样检查字段和时间间隔。

回放 bag 并生成现有 renderer 图像：

```bash
roscore
rosrun dvs_renderer dvs_renderer \
  events:=/dvs/events camera_info:=/dvs/camera_info
rosbag play --clock --pause /workspace/data/prophesee/rosbag/example.bag
```

另开终端：

```bash
rqt_image_view /dvs_rendering
```

## 12. Manifest 字段

每个 RAW/bag 对应 YAML manifest，主要记录：

- 数据类型、路径和 SHA256
- serial、分辨率、编码和固件字段
- OpenEB/wrapper/project commit
- 项目工作区是否 dirty
- 事件数、ROS 消息数和时间区间
- `event_delta_t_s`、回放倍率和时间戳策略
- 源 RAW 路径与 SHA256
- strict/relaxed 模式、差异数和差异比例
- 当前 serial 标定文件的 SHA256
- CLI 默认设置策略，或 Viewer 输入/实际保存设置文件的 SHA256

`project_dirty: true` 表示录制时工作区存在未提交文件或修改。正式论文数据应尽量从已提交 commit 采集，并在采集后立即检查 manifest。

## 13. EVK4 内参标定

EVK4 没有 DAVIS APS 灰度帧，因此不使用 DAVIS 棋盘格流程。本工程复用开源 `dvs_calibration` C++ 核心，以闪烁 LED 点阵从事件流检测几何点。

单目标定入口会过滤无有效 `K/D` 的 CameraInfo，避免上游 pose 计算读取空参数；这不妨碍从未标定状态采样。双目标定必须先加载左右相机各自的有效单目内参。

默认标定板接口：

```text
布局：5 x 5
相邻点距：0.05 m
闪烁频率：约 500 Hz
占空比：约 50%
相邻亮灭转换时间：约 1000 us
允许时间误差：500 us
```

这里的 `blinking_time_us=1000` 是相邻亮灭转换间隔；完整周期约 2 ms，对应约 500 Hz。点距必须使用标定板上 LED 中心的实际物理距离，不能直接沿用默认值。

启动：

```bash
xhost +SI:localuser:root
./scripts/calibrate_prophesee_evk4.sh
```

覆盖参数示例：

```bash
EXTRA_ARGS="dots_w:=5 dots_h:=5 dot_distance:=0.04 blinking_time_us:=1000" \
  ./scripts/calibrate_prophesee_evk4.sh
```

窗口/topic：

```text
/dvs/dvs_rendering                 普通事件累积图
/dvs_calibration/visualization    转换次数图
/dvs_calibration/pattern          检测到的点阵
```

动作：

```bash
./scripts/prophesee_calibration_action.sh reset
./scripts/prophesee_calibration_action.sh start
./scripts/prophesee_calibration_action.sh save
```

推荐顺序：

1. 确认事件流和 LED 闪烁可见。
2. 从不同位置、角度和距离采集足够多的点阵检测。
3. 调用 `start` 计算内参并观察输出。
4. 结果合理后才调用 `save`。
5. 检查 `config/camera_info/prophesee_<serial>.yaml`。

没有 LED 点阵或有效检测时，不要调用 `save`。本次工程验证没有生成 EVK4 内参。

## 14. 标定格式导出

标定保存后执行：

```bash
./scripts/export_prophesee_calibration.sh
```

默认输出：

```text
config/calibration/prophesee/<serial>/camera_info.yaml
config/calibration/prophesee/<serial>/opencv_intrinsics.yaml
config/calibration/prophesee/<serial>/camchain.yaml
config/calibration/prophesee/<serial>/manifest.yaml
```

导出工具检查 ROS 与 OpenCV 的 K/D 矩阵以及分辨率一致性。Kalibr 文件只作为几何参数交换格式；`/dvs/events` 不是图像 topic，不能直接作为 Kalibr 图像输入。默认写入的 `/dvs/dvs_rendering` 是事件累积图，其成像和噪声模型不等于常规相机原始帧。

若未来使用 SDK Pro Calibration，只替换“如何产生内参”这一步。实时驱动、RAW/rosbag、单设备身份校验和三种输出格式可以继续保持。

## 15. EVK4 与现有相机的差异

| 项目 | EVK4-HD | DAVIS 当前 profile |
| --- | --- | --- |
| 原生事件消息 | `prophesee_event_msgs` | `dvs_msgs` |
| 统一适配 | 可选，默认关闭 | 不需要 |
| GUI | 官方 `prophesee_ros_viewer` | `dvs_renderer + rqt_image_view` |
| APS 图像 | 当前链路无 | 有 |
| IMU | 当前链路无 | 有 |
| 原始主档 | OpenEB RAW | 当前主要使用 rosbag |
| 内参标定 | 闪烁 LED 点阵 | APS 棋盘格可用 |

不要把 DAVIS 的 `/dvs/image_raw`、IMU 或棋盘格说明套用到 EVK4。

## 16. 常见问题

### USB 可见但 HAL 报 `LIBUSB_ERROR_ACCESS`

安装规则并重新插拔：

```bash
./scripts/install_prophesee_udev_rules.sh
./scripts/check_usb.sh
```

临时 `chmod` 只对当前 device node 有效，重新插拔后会失效，不能替代 udev。

### profile 报 0 台相机

检查是否有 Viewer、publisher 或其他程序已经独占设备。停止占用进程后等待数秒再试。

### profile 报多台相机

单机 profile 按不同硬件 serial 计数。只使用一台时拔掉额外 EVK；使用两台时改用 `prophesee_evk4_dual*` profile 并提供两个 serial。OpenEB 4.6.2 有时会重复返回同一个 HAL source；项目工具会对完全相同的 source 去重。

### 原生 topic 有数据但没有 `/dvs/events`

适配器默认关闭。使用：

```bash
EXTRA_ARGS="enable_dvs_adapter:=true" \
CAMERA_PROFILE=prophesee_evk4 ./scripts/launch_live_stream.sh
```

### 官方 ROS Viewer 没有 `/dvs_rendering`

这是预期行为。官方 Viewer 直接画事件，不发布 ROS 图像。需要图像 topic 时开启适配器，再运行 `dvs_renderer`。

### RAW 转 bag strict 失败

不要直接改用 relaxed 掩盖问题。先检查磁盘空间、ROS 日志、源 RAW 的 `metavision_file_info`、bag 是否完整关闭，以及 manifest 中的事件差异。只有明确接受最多 0.1% 差异的探索性实验才使用 relaxed。

### CameraInfo 全零

未标定时宽高有效，K/D 为空或为零是正常状态。只有完成真实标定并保存 `prophesee_<serial>.yaml` 后，才能把 CameraInfo 当作有效内参。

## 17. 本次真机验证摘要

验证设备：EVK4-HD / IMX636，serial `00050673`，`1280×720`，EVT3，USB 3.0。

- 原生事件与 CameraInfo topic 正常。
- 默认 1 ms 聚合下事件消息约 800 Hz，随场景活动变化。
- 51 个原生/适配配对批次、32,459 个事件逐字段一致。
- 官方 ROS Viewer GUI 正常订阅并显示原生事件。
- 4.012 秒 RAW 含 2,533,918 个 CD 事件，官方与项目检查器计数一致。
- 2.010 秒 RAW strict 转 bag：1,502,781 对 1,502,781，差异 0。
- 实时 rosbag、`rosbag info/check/play --clock --pause` 和 `dvs_renderer` 均通过。
- 标定节点、检查窗口、服务、serial 路径和临时格式导出通过；未生成 EVK4 内参。
- 双目 launch、namespace、serial 校验和成对 RAW 时间轴逻辑已检查；双目真机与同步精度待验证。

永久宿主 udev 规则仍需要在交互式终端执行一次带密码的安装脚本，并在重新插拔后复查。
