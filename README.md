# event-camera-lab

`event-camera-lab` is a Docker + ROS workspace for repeatable single- and
stereo-camera experiments across multiple event-camera models.

The common runtime path is:

```text
Host Ubuntu -> Docker Ubuntu 20.04 -> ROS Noetic -> event camera driver -> ROS topics
```

The project name and top-level structure are camera-model neutral. Supported
profiles are summarized in [docs/CAMERA_SUPPORT_MATRIX.md](docs/CAMERA_SUPPORT_MATRIX.md).

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

## Documentation

- Full Chinese user manual: [docs/USER_MANUAL.md](docs/USER_MANUAL.md)
- DAVIS calibration and rosbag guide: [docs/DAVIS_CALIBRATION_AND_ROSBAG_GUIDE.md](docs/DAVIS_CALIBRATION_AND_ROSBAG_GUIDE.md)
- Prophesee EVK4-HD guide: [docs/PROPHESEE_EVK4_GUIDE.md](docs/PROPHESEE_EVK4_GUIDE.md)
- Prophesee EVK1-VGA guide: [docs/PROPHESEE_EVK1_VGA_GUIDE.md](docs/PROPHESEE_EVK1_VGA_GUIDE.md)
- Camera support matrix: [docs/CAMERA_SUPPORT_MATRIX.md](docs/CAMERA_SUPPORT_MATRIX.md)
- Upstream source record: [docs/SOURCES.md](docs/SOURCES.md)
- Current validation notes: [docs/VALIDATION.md](docs/VALIDATION.md)
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

They are included as ordinary source folders for this thesis engineering workspace. See [docs/SOURCES.md](docs/SOURCES.md) and the upstream license files for details.
