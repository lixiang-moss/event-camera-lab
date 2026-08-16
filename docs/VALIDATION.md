# Validation Notes

Date: 2026-08-12; dual-GUI validation updated 2026-08-14; DVXplorer and calibration/rosbag validation updated 2026-08-16

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
- `rospack find dvxplorer_ros_driver` succeeds.
- `roslaunch event_camera_lab_bringup current_live_stream.launch --nodes` resolves `/dvs/event_camera_driver`.
- `roslaunch event_camera_lab_bringup dual_live_stream.launch --nodes` resolves `/cam0/event_camera_driver` and `/cam1/event_camera_driver`.
- `CAMERA_PROFILE=current_davis_dual EXTRA_ARGS='--nodes' ./scripts/launch_live_stream.sh` resolves the same two driver nodes.
- `roslaunch event_camera_lab_bringup dual_live_stream_with_renderer.launch --nodes` additionally resolves `/cam0/dvs_renderer`, `/cam0/image_view`, `/cam1/dvs_renderer`, and `/cam1/image_view`.
- Live driver starts when launched through `./scripts/launch_live_stream.sh`.
- `/dvs/events` publishes at about 30 Hz during the short validation run.
- The dual GUI profile was live-tested with two DAVIS346 cameras connected at the same time.
- `/cam0/events` and `/cam1/events` each published at about 30 Hz.
- `/cam0/dvs_rendering` and `/cam1/dvs_rendering` published at about 41 Hz and 40 Hz respectively, as `346x260` `bgr8` images.
- The two `rqt_image_view` processes subscribed independently to `/cam0/dvs_rendering` and `/cam1/dvs_rendering`.
- `dvxplorer_live_stream.launch` resolves `/dvs/event_camera_driver` without GUI nodes.
- `dvxplorer_live_stream_with_renderer.launch` additionally resolves `/dvs_renderer`, `/image_view`, and `/rqt_reconfigure`.
- `CAMERA_PROFILE=dvxplorer` and `CAMERA_PROFILE=dvxplorer_with_renderer` resolve the project-owned bring-up launch files.
- `./scripts/record_events.sh` successfully records a short bag file to `data/`.
- The image includes `camera_calibration`; `rospack find camera_calibration` and `cameracalibrator.py --help` succeed. The package also installs its `image_geometry` dependency.
- The Docker entrypoint preserves command arguments until after ROS setup, so direct container commands ending in `--help` no longer leak those arguments into catkin's setup utility.
- With one DAVIS346 connected and APS enabled, `/dvs/image_raw` published `346x260` `mono8` images at about 40 Hz, and `/dvs/set_camera_info` was available.
- `cameracalibrator.py` started its GUI and subscribed to `/dvs/image_raw`. No samples were collected and `CALIBRATE`, `SAVE`, and `COMMIT` were not used.
- A 4-second single-camera validation bag contained 112 `/dvs/events` messages, 150 `/dvs/image_raw` messages, and 3740 `/dvs/imu` messages over 3.7 seconds. `rosbag info` and `rosbag check` both succeeded.
- `rosbag play --clock --pause` started in the expected paused state. During looped playback, events published at about 30 Hz and `/dvs_rendering` at about 39-41 Hz.
- An explicit `rqt_image_view /dvs_rendering` command subscribed successfully during playback. The upstream `renderer_mono.launch` rqt node opened without reliably selecting the rendering topic, so the guide now starts renderer and image view separately.
- With no calibration YAML loaded, `/dvs/camera_info` did not publish messages and therefore was absent from the validation bag.
- The dual-bag renderer commands received a namespace-only static check: `/cam0` and `/cam1` inputs, outputs, and auxiliary topics resolved separately. No two-camera hardware run was performed for this calibration/rosbag update.

Notes:

- The live driver must run as root inside the privileged container because the USB device node is owned by `root:root` and requires write access.
- A missing camera calibration file warning appeared for `/root/.ros/camera_info/DAVIS-00000889.yaml`; this does not block event streaming.
- Some imported upstream ROS packages emit CMake deprecation warnings because they declare old CMake compatibility. The packages still build successfully.
- The dual profiles intentionally leave `serial_number` empty, so physical camera assignment to `/cam0` and `/cam1` is not stable across reconnects or restarts.
- No DVXplorer hardware was connected during the 2026-08-16 validation, so its profiles were build- and launch-validated but not live-stream validated.
- The calibration validation only confirmed dependencies, topics, services, image input, and GUI startup. It did not create or write camera intrinsics.
- Only one DAVIS346 was connected for the calibration and rosbag validation in this update.
