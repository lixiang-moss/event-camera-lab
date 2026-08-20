# Validation Notes

Date: 2026-08-12; dual-GUI validation updated 2026-08-14; DVXplorer and calibration/rosbag validation updated 2026-08-16; EVK4-HD validation updated 2026-08-19; EVK1-VGA validation updated 2026-08-20

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

EVK4-HD validated items:

- The Docker image builds OpenEB `4.6.2` from commit `53b3618935f90dcc0f64993ccbb79514384404b0` with the required submodule and installs it under `/opt/metavision`.
- `/opt/metavision/share/openeb-build-info.txt` records the verified OpenEB repository commit. `metavision_software_info -c` reports the vendor's internal SDK commit embedded in this release, not the OpenEB repository commit.
- `metavision_software_info`, `metavision_platform_info`, `metavision_viewer`, `metavision_file_info` and the Prophesee HAL plugin are present in the final image.
- `prophesee_ros_wrapper` `4.6.2`, commit `8eba7cecd19f31585032188a5daa5908c848e2c4`, builds as ordinary workspace source.
- OpenEB identifies the connected device as Prophesee IMX636 HD / EVK4-HD, serial `00050673`, `system_ID=49`, `1280x720`, EVT3, over USB 3.0. No firmware incompatibility warning appeared.
- The pure profile publishes `/prophesee/camera/cd_events_buffer` and `/prophesee/camera/camera_info`, without enabling `/dvs/events` or GUI by default.
- The official ROS Viewer profile launches and subscribes to both native topics. It intentionally produces no `/dvs_rendering` image topic.
- With the adapter enabled, `/dvs/events` is `dvs_msgs/EventArray`, `/dvs/camera_info` is `sensor_msgs/CameraInfo`, and `/dvs/set_camera_info` is available.
- A paired live comparison checked 51 native/adapted batches and 32,459 events; dimensions, coordinates, polarity, per-event timestamps and per-batch counts matched.
- Default `event_delta_t=0.001` produced roughly 800 event messages per second in the tested scene. This rate varies with activity and callback scheduling.
- A 4.012-second RAW contained 2,533,918 CD events. `metavision_file_info` and the project RAW checker agreed on serial, dimensions, EVT3, duration and event count.
- A 2.010-second RAW strict conversion produced 1,502,781 RAW events and 1,502,781 bag events, with difference 0.
- Live normalized rosbag recording, `rosbag info`, `rosbag check`, `rosbag play --clock --pause`, and playback through `dvs_renderer` succeeded. The renderer output was `1280x720` `bgr8`.
- The EVK4 calibration profile launched the driver, adapter, renderer, `dvs_calibration`, three rqt image views and the start/reset/save services. Only reset was called; no EVK4 calibration YAML was created.
- The ROS CameraInfo to OpenCV/Kalibr exporter passed matrix and resolution checks using a temporary structural fixture outside the persistent EVK4 calibration path.
- The upstream `prophesee_ros_wrapper` and `rpg_dvs_ros` sources were not modified.

EVK1-VGA validated items:

- `event-camera-lab:openeb31-noetic` builds OpenEB `3.1.2` from commit `04022c2f1dac338d4dc6ec85d50fcfafd74f9989` and uses separate `build_openeb31`, `devel_openeb31`, and `logs_openeb31` spaces.
- OpenEB identifies the connected device as Prophesee Gen 3.0 VGA, serial `00002433`, `system_ID=21`, `640x480`, EVT2, over USB 3.0. The EVK1 profile accepted it; the OpenEB 4.6 service did not expose it as an EVK4 device.
- The single-camera profile publishes `dvs_msgs/EventArray`, `sensor_msgs/CameraInfo`, and `event_camera_msgs/ExternalTriggerArray`; `/dvs/set_camera_info` is available.
- The GUI profile starts `dvs_renderer` and rqt; the renderer advertises `/dvs_rendering`, and the rqt process subscribes to it.
- A project-recorded OpenEB RAW decoded to 272 CD events and 0 trigger events. The low count came from a static scene and is not a throughput result.
- Strict RAW-to-bag conversion produced 272 RAW events and 272 bag events, with 0 triggers on both sides. `rosbag info` and `rosbag check` succeeded.
- A short live bag command completed and passed `rosbag info/check`; the static scene produced no new CD events during that interval, so it does not demonstrate sustained live rate.
- A saved OpenEB bias file loaded successfully through `BIAS_FILE`.
- The intrinsic calibration profile started the driver, renderer, `dvs_calibration`, three rqt windows, and start/reset/save services. No calibration action was executed and no YAML was generated.
- EVK1, EVK4, and DVXplorer stereo launch files resolve two drivers, two isolated renderers, and two image-view nodes. EVK1 stereo rejects missing, duplicate, and disconnected serials before launch.
- EVK1 stereo hardware, master/slave wiring, external pulses, stereo calibration, and synchronization accuracy remain unverified because only one EVK1-VGA was connected.
- After the independent review fixes, a new 2-second RAW closed through `Camera::stop()`, contained 236 CD events and 0 triggers, and recorded the generated bias sidecar SHA256. Strict conversion produced 236/236 CD events and 0/0 triggers.
- The calibration CameraInfo gate received the uncalibrated `640x480` message with empty `D` and zero `K`, withheld it from `/dvs/calibration_camera_info`, and left the calibration services running.
- A live rosbag run read the actual `event_delta_t=0.0001`, `sync_mode=standalone`, and bias SHA256 from the running node. An explicit incorrect `EVENT_DELTA_T=0.001` assertion was rejected before recording.
- The paired-bag merge utility was tested with interleaved synthetic cam0/cam1 timestamps and with a 1,750-message validation bag whose events and CameraInfo were not globally ordered by header time. Both outputs were monotonic; the real bag retained the same topic counts, duration, and time range, and `rosbag check` passed.
- Offline RAW profile validation accepts EVK1 `system_ID=21/28` and EVK4 `system_ID=49`; a same-geometry synthetic RAW identity with `system_ID=41` was rejected.

Notes:

- The live driver must run as root inside the privileged container because the USB device node is owned by `root:root` and requires write access.
- A missing camera calibration file warning appeared for `/root/.ros/camera_info/DAVIS-00000889.yaml`; this does not block event streaming.
- Some imported upstream ROS packages emit CMake deprecation warnings because they declare old CMake compatibility. The packages still build successfully.
- DAVIS and DVXplorer dual profiles leave `serial_number` empty by default, so physical assignment is not stable unless both serials are supplied. Prophesee dual profiles require two different serials.
- No DVXplorer hardware was connected during the 2026-08-16 validation, so its profiles were build- and launch-validated but not live-stream validated.
- The calibration validation only confirmed dependencies, topics, services, image input, and GUI startup. It did not create or write camera intrinsics.
- Only one DAVIS346 was connected for the calibration and rosbag validation in this update.
- Only one EVK4-HD was connected for the EVK4 validation.
- Permanent installation of `/etc/udev/rules.d/88-cyusb.rules` requires one interactive host `sudo` run. Validation used the current USB node permission; replug validation remains after that installation.
