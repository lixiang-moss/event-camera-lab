# Validation Notes

Date: 2026-08-12

Host:

- Ubuntu 26.04
- Docker 29.1.3
- Docker Compose 2.40.3

Validated items:

- Docker image `event-camera-lab:noetic` builds successfully.
- Container ROS distro is `noetic`.
- `libcaer-dev` is installed in the container: `3.3.17-1~focal`.
- Host `lsusb` sees the current event camera.
- Container `lsusb` sees `iniVation DAVIS 346`.
- ROS workspace builds successfully with the default package set.
- `rospack find davis_ros_driver`, `dvs_renderer`, and `event_camera_lab_bringup` all succeed.
- `roslaunch event_camera_lab_bringup current_live_stream.launch --nodes` resolves `/dvs/event_camera_driver`.
- Live driver starts when launched through `./scripts/launch_live_stream.sh`.
- `/dvs/events` publishes at about 30 Hz during the short validation run.
- `./scripts/record_events.sh` successfully records a short bag file to `data/`.

Notes:

- The live driver must run as root inside the privileged container because the USB device node is owned by `root:root` and requires write access.
- A missing camera calibration file warning appeared for `/root/.ros/camera_info/DAVIS-00000889.yaml`; this does not block event streaming.
- Some imported upstream ROS packages emit CMake deprecation warnings because they declare old CMake compatibility. The packages still build successfully.
