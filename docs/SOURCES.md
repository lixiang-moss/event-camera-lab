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

## Notes

- The imported repositories are stored as ordinary source folders, not Git submodules.
- This project does not attempt to track or merge future upstream changes automatically.
- If future work needs a newer driver version, record the new source URL, commit, import date, and reason here before replacing or adding source code.
