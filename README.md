# event-camera-lab

`event-camera-lab` is a Docker + ROS workspace for event camera bring-up and future multi-camera experiments.

The current first milestone is to run a live event stream from the available camera through:

```text
Host Ubuntu -> Docker Ubuntu 20.04 -> ROS Noetic -> event camera driver -> ROS topics
```

The project name and folder structure are intentionally camera-model neutral. The current DAVIS driver is only the first validation profile.

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

This uses `roslaunch`, so it starts a ROS master automatically when one is not already running.

In another terminal, inspect topics:

```bash
./scripts/check_topics.sh
```

For either two-camera profile, check `/cam0/events` and `/cam1/events`
separately. Camera-to-namespace assignment is not stable because these profiles
intentionally do not bind devices by serial number.

## Documentation

- Full Chinese user manual: [docs/USER_MANUAL.md](docs/USER_MANUAL.md)
- Upstream source record: [docs/SOURCES.md](docs/SOURCES.md)
- Current validation notes: [docs/VALIDATION.md](docs/VALIDATION.md)
- Thesis project plan: [event_camera_thesis_project_plan.md](event_camera_thesis_project_plan.md)

## Source Notice

This repository includes source code from:

- `uzh-rpg/rpg_dvs_ros`
- `catkin/catkin_simple`

They are included as ordinary source folders for this thesis engineering workspace. See [docs/SOURCES.md](docs/SOURCES.md) and the upstream license files for details.
