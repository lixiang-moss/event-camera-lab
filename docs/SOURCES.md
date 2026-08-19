# Sources

This file records the third-party source code included in this workspace.

## rpg_dvs_ros

- Repository: `uzh-rpg/rpg_dvs_ros`
- URL: `https://github.com/uzh-rpg/rpg_dvs_ros`
- Branch imported: `master`
- Commit imported: `b7fce27a2342221209c39f24d5027ea9f4ef7ceb`
- Imported on: `2026-08-12`
- Local path: `ros_ws/src/rpg_dvs_ros`
- License: MIT, see `ros_ws/src/rpg_dvs_ros/LICENSE`

Purpose in this project:

- Provides ROS1 drivers and tools for DVS/DAVIS/DVXplorer event cameras.
- The current bring-up profile uses its DAVIS driver package as the first hardware validation path.

## catkin_simple

- Repository: `catkin/catkin_simple`
- URL: `https://github.com/catkin/catkin_simple`
- Branch imported: `master`
- Commit imported: `0e62848b12da76c8cc58a1add42b4f894d1ac21e`
- Imported on: `2026-08-12`
- Local path: `ros_ws/src/catkin_simple`

Purpose in this project:

- Build helper required by the imported `rpg_dvs_ros` ROS packages.

## OpenEB

- Repository: `prophesee-ai/openeb`
- URL: `https://github.com/prophesee-ai/openeb`
- Version built: `4.6.2`
- Commit built: `53b3618935f90dcc0f64993ccbb79514384404b0`
- Recorded on: `2026-08-19`
- Container install prefix: `/opt/metavision`
- License: OpenEB open-source license, copied in the image to `/opt/metavision/share/licenses/openeb/LICENSE_OPEN`

Purpose in this project:

- Provides HAL, EVK4-HD/IMX636 plugin, Driver API, Viewer, RAW decoding and file tools.
- Docker clones the full tagged repository with submodules and verifies the exact commit during image build.
- OpenEB source is built in a Docker stage and is not vendored into this Git repository.

## prophesee_ros_wrapper

- Repository: `prophesee-ai/prophesee_ros_wrapper`
- URL: `https://github.com/prophesee-ai/prophesee_ros_wrapper`
- Version imported: `4.6.2`
- Commit imported: `8eba7cecd19f31585032188a5daa5908c848e2c4`
- Imported on: `2026-08-19`
- Local path: `ros_ws/src/prophesee_ros_wrapper`
- License: Apache-2.0, see `ros_ws/src/prophesee_ros_wrapper/LICENSE`

Purpose in this project:

- Provides `prophesee_event_msgs`, the live ROS publisher and the official ROS event viewer.
- Imported as an ordinary source folder without its internal `.git` directory.
- The upstream wrapper source is unmodified; project behavior is added in `event_camera_prophesee_tools` and `event_camera_lab_bringup`.

## Notes

- Imported repositories are stored as ordinary source folders, not Git submodules.
- This project does not attempt to track or merge future upstream changes automatically.
- If future work needs a newer driver version, record the new source URL, commit, import date, and reason here before replacing or adding source code.
