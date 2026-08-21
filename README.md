# event-camera-lab

`event-camera-lab` is a Docker + ROS workspace for repeatable single- and
stereo-camera experiments across multiple event-camera models.

The common runtime path is:

```text
Host Ubuntu -> Docker Ubuntu 20.04 -> ROS Noetic -> event camera driver -> ROS topics
```

The project name and top-level structure are camera-model neutral. Supported
profiles are summarized in [docs/相机支持矩阵.md](docs/相机支持矩阵.md).

## Quick Start

Build the Docker image:

```bash
./scripts/build_image.sh
```

Check USB visibility on the host and inside the container:

```bash
./scripts/check_usb.sh
```

Build the ROS workspace:

```bash
./scripts/build_workspace.sh
```

Start the current live stream profile:

```bash
./scripts/launch_live_stream.sh
```

Start the two-camera profile when two compatible cameras are connected:

```bash
CAMERA_PROFILE=current_davis_dual ./scripts/launch_live_stream.sh
```

To open one live event-view window for each camera, allow Docker to use X11 and
start the dual GUI profile:

```bash
xhost +local:docker
CAMERA_PROFILE=current_davis_dual_with_renderer ./scripts/launch_live_stream.sh
```

The two rendered image topics are `/cam0/dvs_rendering` and
`/cam1/dvs_rendering`.

Start a DVXplorer without or with the event-view GUI:

```bash
CAMERA_PROFILE=dvxplorer ./scripts/launch_live_stream.sh
CAMERA_PROFILE=dvxplorer_with_renderer ./scripts/launch_live_stream.sh
```

Both DVXplorer profiles use project-owned launch files and publish events on
`/dvs/events`. The GUI profile renders them on `/dvs_rendering`.

For a Prophesee EVK4-HD, install the host udev rule once, then start the
project-owned pure-driver or GUI profile:

```bash
./scripts/install_prophesee_udev_rules.sh
CAMERA_PROFILE=prophesee_evk4 ./scripts/launch_live_stream.sh
CAMERA_PROFILE=prophesee_evk4_with_renderer ./scripts/launch_live_stream.sh
```

EVK4 keeps its native topics under `/prophesee/camera/*`. The optional
`dvs_msgs` adapter is enabled explicitly:

```bash
CAMERA_PROFILE=prophesee_evk4 \
  EXTRA_ARGS="enable_dvs_adapter:=true" \
  ./scripts/launch_live_stream.sh
```

Record the original OpenEB RAW stream or the normalized ROS interface:

```bash
DURATION=60 ./scripts/record_prophesee_raw.sh
DURATION=60 ./scripts/record_prophesee_rosbag.sh
```

See the EVK4 guide before collecting experiment data; RAW is the original
archive and rosbag is the derived ROS format.

For an EVK1-VGA, use the isolated OpenEB 3.1 environment. The scripts select
the correct image and catkin space from `CAMERA_PROFILE`:

```bash
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/build_image.sh
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/build_workspace.sh
CAMERA_PROFILE=prophesee_evk1_vga ./scripts/launch_live_stream.sh
CAMERA_PROFILE=prophesee_evk1_vga_with_renderer ./scripts/launch_live_stream.sh
```

EVK1/EVK4 stereo profiles require two distinct serials. DAVIS/DVXplorer
stereo profiles keep serials optional, with `REQUIRE_SERIALS=true` available
for fixed left/right identity. See each camera guide before collecting thesis
data.

This uses `roslaunch`, so it starts a ROS master automatically when one is not already running.

In another terminal, inspect topics:

```bash
./scripts/check_topics.sh
```

For any two-camera profile, check `/cam0/events` and `/cam1/events` separately.

## NRV DELTA10 Viewer

NRV DELTA10 uses a separate Ubuntu 22.04 container with the official DVS
Viewer. It does not install ROS and does not alter the Ubuntu 20.04 + Noetic
camera runtime.

Prepare the pinned upstream Viewer locally, then build and launch it:

```bash
mkdir -p third_party/nrv
git clone https://github.com/nrvcorp/DVS_Viewer.git third_party/nrv/DVS_Viewer
git -C third_party/nrv/DVS_Viewer checkout 460512cec02255a627a3baa2737d9a496345d8fc
./scripts/build_nrv_viewer_image.sh
./scripts/check_nrv_usb.sh
./scripts/launch_nrv_viewer.sh
```

The current NRV stage covers the official GUI, `.dvs` recording/playback,
HDF5 export, and the official calibration mode. ROS and rosbag conversion are
gated on obtaining the developer SDK with headers.

## Documentation

- Full Chinese user manual: [docs/项目使用手册.md](docs/项目使用手册.md)
- DAVIS calibration and rosbag guide: [docs/DAVIS相机标定与ROSBag指南.md](docs/DAVIS相机标定与ROSBag指南.md)
- Prophesee EVK4-HD guide: [docs/EVK4-HD相机使用指南.md](docs/EVK4-HD相机使用指南.md)
- Prophesee EVK1-VGA guide: [docs/EVK1-VGA相机使用指南.md](docs/EVK1-VGA相机使用指南.md)
- NRV DELTA10 Viewer guide: [docs/NRV_DELTA_GUIDE.md](docs/NRV_DELTA_GUIDE.md)
- NRV DELTA10 SDK/ROS roadmap: [docs/NRV_DELTA_ROADMAP.md](docs/NRV_DELTA_ROADMAP.md)
- Camera support matrix: [docs/相机支持矩阵.md](docs/相机支持矩阵.md)
- Upstream source record: [docs/第三方源码记录.md](docs/第三方源码记录.md)
- Current validation notes: [docs/环境验证记录.md](docs/环境验证记录.md)
- Thesis project plan: [event_camera_thesis_project_plan.md](event_camera_thesis_project_plan.md)

## Source Notice

Project-authored code is licensed under the root [MIT License](LICENSE).
Vendored third-party source remains under its own upstream license.

This repository includes source code from:

- `uzh-rpg/rpg_dvs_ros`
- `catkin/catkin_simple`
- `prophesee-ai/prophesee_ros_wrapper`

The Docker image builds OpenEB from the pinned upstream source during image
construction; OpenEB is not vendored into this repository.

The NRV Viewer is supplied through an ignored local checkout and is not
redistributed by this repository. See the NRV guide and source record for its
fixed upstream commit and current license boundary.

They are included as ordinary source folders for this thesis engineering workspace. See [docs/第三方源码记录.md](docs/第三方源码记录.md) and the upstream license files for details.
