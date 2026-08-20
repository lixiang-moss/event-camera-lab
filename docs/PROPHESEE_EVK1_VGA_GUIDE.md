# Prophesee EVK1-VGA 使用指南

## 1. 支持范围

本工程支持 Prophesee EVK1 Gen3/Gen3.1 VGA，固定分辨率为 `640×480`，并只接受 OpenEB `system_ID` `21` 或 `28`。
不提供 EVK1-HD profile，也不作 EVK1-HD 兼容声明。

固定环境：

| 组件 | 版本 | Commit |
| --- | --- | --- |
| OpenEB | `3.1.2` | `04022c2f1dac338d4dc6ec85d50fcfafd74f9989` |
| Container | Ubuntu 20.04 | `event-camera-lab:openeb31-noetic` |
| ROS | Noetic | ROS1 |

OpenEB 3.1 与 EVK4 使用的 OpenEB 4.6 位于不同镜像和 catkin 空间，不能在同一进程中混用。

## 2. 首次安装

```bash
cd /home/lx/ec_xiangli
./scripts/install_prophesee_udev_rules.sh
```

重新插拔相机后构建 EVK1 环境：

```bash
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/build_image.sh
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/build_workspace.sh
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/check_usb.sh
```

脚本会自动选择 `event-camera-openeb31-ros` service 和 `devel_openeb31`，无需手工切换容器。

## 3. 单目实时模式

纯驱动：

```bash
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/launch_live_stream.sh
```

GUI：

```bash
xhost +SI:localuser:root
CAMERA_PROFILE=prophesee_evk1_vga_with_renderer ./scripts/launch_live_stream.sh
```

接口：

```text
/dvs/events           dvs_msgs/EventArray
/dvs/camera_info      sensor_msgs/CameraInfo
/dvs/set_camera_info  sensor_msgs/SetCameraInfo
/dvs/ext_trigger      event_camera_msgs/ExternalTriggerArray
/dvs_rendering        sensor_msgs/Image（GUI profile）
```

单目 profile 只允许检测到一台 Prophesee 相机，并校验分辨率、sensor generation 和 `system_ID`。默认自动读取 serial；设置 `CAMERA_SERIAL` 时，它只用于核对连接设备。

事件聚合窗口默认为 `1 ms`：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
  EXTRA_ARGS="event_delta_t:=0.0001" \
  ./scripts/launch_live_stream.sh
```

上述命令改为 `100 us`。论文实验必须记录该参数。静止场景事件很少，检查画面时应移动相机或场景物体。

加载固定 bias：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
  BIAS_FILE=/workspace/config/prophesee/evk1_vga.bias \
  ./scripts/launch_live_stream.sh
```

## 4. 双目实时模式

双目必须提供两个不同 serial，以固定物理相机与 `/cam0`、`/cam1` 的对应关系：

```bash
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk1_vga_dual \
  ./scripts/launch_live_stream.sh
```

双窗口 GUI：

```bash
xhost +SI:localuser:root
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk1_vga_dual_with_renderer \
  ./scripts/launch_live_stream.sh
```

双目接口位于 `/cam0/*` 和 `/cam1/*`，渲染图分别为 `/cam0/dvs_rendering`、`/cam1/dvs_rendering`。

默认 `SYNC_MODE=standalone`。接好厂商支持的同步线后才能使用：

```bash
SYNC_MODE=master_slave \
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk1_vga_dual \
  ./scripts/launch_live_stream.sh
```

此模式将 cam1 配置为 slave、cam0 配置为 master。当前尚未进行双机、同步线或外部脉冲真机验证，因此不能把两路 ROS 时间戳相近当成同步精度证明。

## 5. RAW 与 rosbag

单目 RAW：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
DURATION=60 ./scripts/record_prophesee_raw.sh
```

单目 ROS bag 需要先启动单目 profile，再在另一终端运行：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
DURATION=60 ./scripts/record_prophesee_rosbag.sh
```

单目 RAW 回放与 strict 转换：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
RAW_FILE=data/prophesee/evk1_vga/raw/example.raw \
WITH_VIEWER=true ./scripts/replay_prophesee_raw.sh

CAMERA_PROFILE=prophesee_evk1_vga \
RAW_FILE=data/prophesee/evk1_vga/raw/example.raw \
INTEGRITY_MODE=strict ./scripts/convert_prophesee_raw_to_rosbag.sh
```

双目 RAW：

```bash
CAMERA_PROFILE=prophesee_evk1_vga_dual \
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
DURATION=60 ./scripts/record_prophesee_raw.sh
```

成对回放与转换：

```bash
CAMERA_PROFILE=prophesee_evk1_vga_dual \
CAM0_RAW_FILE=data/prophesee/evk1_vga/raw/cam0.raw \
CAM1_RAW_FILE=data/prophesee/evk1_vga/raw/cam1.raw \
WITH_VIEWER=true ./scripts/replay_prophesee_raw_pair.sh

CAMERA_PROFILE=prophesee_evk1_vga_dual \
CAM0_RAW_FILE=data/prophesee/evk1_vga/raw/cam0.raw \
CAM1_RAW_FILE=data/prophesee/evk1_vga/raw/cam1.raw \
INTEGRITY_MODE=strict ./scripts/convert_prophesee_raw_pair_to_rosbag.sh
```

数据位于：

```text
data/prophesee/evk1_vga/raw/
data/prophesee/evk1_vga/rosbag/
data/prophesee/evk1_vga/manifests/
```

RAW 是原始主档，rosbag 是 ROS 算法接口。回放和转换也会校验 `system_ID=21/28`，避免用其他 Prophesee 型号的 RAW 进入 EVK1 profile。manifest 记录 serial、版本、事件/trigger 数、同步模式、bias/标定哈希和数据 SHA256。`strict` 要求 RAW 与 bag 的 CD event 和 trigger 数量完全一致。

双 RAW 转换先分别录制两路临时 bag，再将每个 topic 按首事件或 header 时间流式归并为最终 bag。最终 bag 使用事件时间作为记录时间；任一 topic 内时间倒退会使转换失败。临时 bag 在转换结束后删除。

实时 rosbag manifest 从正在运行的节点读取 `event_delta_t`、同步角色和 bias 路径。录包时设置 `EVENT_DELTA_T` 或 `SYNC_MODE` 只作为期望值断言，不会覆盖 driver。

## 6. 标定与 Trigger

单目 LED 点阵标定入口：

```bash
xhost +SI:localuser:root
CAMERA_PROFILE=prophesee_evk1_vga_calibration \
  ./scripts/launch_live_stream.sh
```

双目标定入口：

```bash
CAM0_SERIAL=00000001 CAM1_SERIAL=00000002 \
CAMERA_PROFILE=prophesee_evk1_vga_dual_calibration \
  ./scripts/launch_live_stream.sh
```

默认标定板为 `5×5` LED 点阵、点距 `0.05 m`。没有真实标定板和有效采样时，不执行 save，也不生成替代内参或外参。CameraInfo 文件按 serial 保存在 `config/camera_info/prophesee_<serial>.yaml`，默认不提交 Git。

单目标定允许从未标定状态采样；项目门控会阻止空 `K/D` 进入上游 pose 计算。双目标定必须先为 cam0、cam1 各自生成有效单目内参；缺少任一路有效 CameraInfo 时，双目标定不会接受点阵配对。

真实标定 YAML 生成后可导出 ROS、OpenCV 和 Kalibr 几何文件：

```bash
CAMERA_PROFILE=prophesee_evk1_vga \
CAMERA_SERIAL=00002433 ./scripts/export_prophesee_calibration.sh
```

Kalibr 文件仅作为几何参数交换格式；`/dvs/events` 不能直接当作 Kalibr 图像输入。

Trigger In channel 0 默认启用。没有外部脉冲时 `/dvs/ext_trigger` 或 `/cam*/ext_trigger` 存在但可以没有消息。未实测外部脉冲前，不对 trigger 延迟和抖动作定量声明。

## 7. 当前验证边界

- 已用一台 EVK1 Gen3 VGA、serial `00002433` 验证单目驱动、GUI、bias、RAW、rosbag、strict 转换和标定程序启动。
- 双目 launch、serial 校验、namespace、共享 RAW 回放时间轴和失败路径已检查。
- 双目实时画面、硬件同步、外部 Trigger 和双目标定尚待两台相机及配套硬件验证。
