rpg_dvs_ros
===========

# 免责声明与许可证

RPG ROS DVS 软件包支持 ROS Kinetic（Ubuntu 16.04）、ROS Melodic（Ubuntu 18.04）和 ROS Noetic（Ubuntu 20.04）。

这是研究代码，可能会经常变化，并且不保证适用于某个特定用途。

源代码基于 **MIT License** 发布。


# 软件包概览

ROS DVS 软件包为 [Dynamic Vision Sensors（DVS/DAVIS）](https://inivation.com/dvp/) 提供 C++ 驱动。
即使你没有 DAVS 或 DAVIS 设备，也仍然可以[使用这个驱动读取预先录制的事件数据文件（见下面的示例）](#ExampleEventCameraDataset)。
该软件包还提供了用于内参标定和双目标定的标定工具。
如果想了解更多事件相机相关内容，可以访问 [Institute of Neuroinformatics](http://siliconretina.ini.uzh.ch/wiki/index.php) 的网站。
该软件包基于 [libcaer](https://gitlab.com/inivation/libcaer/)。

作者：Elias Mueggler, Basil Huber, Luca Longinotti, Tobi Delbruck


## 论文引用

如果你在学术场景中使用本项目，请引用以下论文：

* E. Mueggler, B. Huber, D. Scaramuzza: **Event-based, 6-DOF Pose Tracking for High-Speed Maneuvers**. IEEE/RSJ International Conference on Intelligent Robots and Systems (IROS), Chicago, 2014. ([PDF](http://rpg.ifi.uzh.ch/docs/IROS14_Mueggler.pdf))
* P. Lichtsteiner, C. Posch, T. Delbruck: **A 128×128 120dB 15us Latency Asynchronous Temporal Contrast Vision Sensor**. IEEE Journal of Solid State Circuits, Feb. 2008, 43(2), pp. 566-576. ([PDF](https://www.ini.uzh.ch/~tobi/wiki/lib/exe/fetch.php?media=lichtsteiner_dvs_jssc08.pdf))
* C. Brandli, R. Berner, M. Yang, S. C. Liu and T. Delbruck: **A 240 × 180 130 dB 3 us Latency Global Shutter Spatiotemporal Vision Sensor**. IEEE Journal of Solid-State Circuits, Oct. 2014, 49(10), pp. 2333-2341. ([Link](ieeexplore.ieee.org/document/6889103))


# 驱动安装

注意：下面说明中凡是出现 `kinetic` 的地方，都应替换为你当前使用的 ROS 发行版名称。

1. 安装 ROS 依赖：
*   `$ sudo apt-get install ros-kinetic-camera-info-manager`
*   `$ sudo apt-get install ros-kinetic-image-view`

2. 安装 libcaer（先按照 [iniVation 文档](https://docs.inivation.com/software/dv/gui/install.html#ubuntu-linux) 添加所需软件源）：
*   `$ sudo apt-get install libcaer-dev`

3. 安装 catkin tools：
*   `$ sudo apt-get install python3-catkin-tools`（如果使用 ROS Melodic 或 ROS Noetic）。
*   `$ sudo apt-get install python-catkin-tools`（如果使用 ROS Kinetic）。

4. 创建 catkin 工作空间（如果你还没有创建）：
*   `$ cd`
*   `$ mkdir -p catkin_ws/src`
*   `$ cd catkin_ws`
*   `$ catkin config --init --mkdirs --extend /opt/ros/kinetic --merge-devel --cmake-args -DCMAKE_BUILD_TYPE=Release`

5. 克隆 `catkin_simple` 软件包（https://github.com/catkin/catkin_simple），它会用于构建 DVS/DAVIS 驱动包：
*   `$ cd ~/catkin_ws/src`
*   `$ git clone https://github.com/catkin/catkin_simple.git`

6. 克隆本仓库：
*   `$ cd ~/catkin_ws/src`
*   `$ git clone https://github.com/uzh-rpg/rpg_dvs_ros.git`

7. 构建软件包：
* `$ catkin build dvs_ros_driver`（如果你使用 DVS128）
* `$ catkin build davis_ros_driver`（如果你使用 DAVIS）
* `$ catkin build dvxplorer_ros_driver`（如果你使用 DVXplorer）

8. 你可以运行项目提供的 launch 文件来测试安装。它会启动驱动（DVS 或 DAVIS）和 renderer（图像查看器）。
    1. 首先构建 renderer：
        * `$ catkin build dvs_renderer`
    2. 配置环境：
        * `$ source ~/catkin_ws/devel/setup.bash`，如果使用 zsh，则执行 `$ source ~/catkin_ws/devel/setup.zsh`
    3. 然后启动示例：
        * `$ roslaunch dvs_renderer dvs_mono.launch`（如果你使用 DVS128）
        * `$ roslaunch dvs_renderer davis_mono.launch`（如果你使用 DAVIS）
        * `$ roslaunch dvs_renderer dvxplorer_mono.launch`（如果你使用 DVXplorer）
    你应该会看到类似下面的图像（以 DAVIS 为例）：

        ![dvs_rendering_screenshot_19 04 2017](https://cloud.githubusercontent.com/assets/8024432/25172262/b96baaa0-24f0-11e7-9c3e-e33f6d398a4a.png)

9. **即使你没有 DAVIS，也仍然可以使用这个驱动读取录制文件**，例如 [The Event Camera Dataset and Simulator](http://rpg.ifi.uzh.ch/davis_data.html) 中的数据。
   **示例**：<a name="ExampleEventCameraDataset"></a>
    1. 下载一个数据集序列，例如 [slider_depth.bag](http://rpg.ifi.uzh.ch/datasets/davis/slider_depth.bag)
    2. 打开终端并启动 roscore：
     * `$ roscore`
    3. 在另一个终端中播放 bag：
     * `$ rosbag play -l path-to-file/slider_depth.bag`
    4. 在另一个终端中启动 DVS/DAVIS renderer：
     * `$ roslaunch dvs_renderer renderer_mono.launch`
    你应该会看到类似下面的动态图像：

        ![slider_depth_renderer](https://cloud.githubusercontent.com/assets/8024432/25312371/9afd4180-2817-11e7-9e33-cdaa8af1e6ed.png)

10. 可选：如果使用 DAVIS 的**实时数据流**（即不是录制文件），你可以用 dynamic reconfigure GUI 按需调整 DVS/DAVIS 参数。运行：
    * `$ rosrun rqt_reconfigure rqt_reconfigure`
   随后会出现一个窗口。在左侧面板中选择 `davis_ros_driver`，你应该会看到如下 GUI，它允许你修改传感器参数。

   ![davis_ros_driver_rqt_reconfigure](https://cloud.githubusercontent.com/assets/8024432/25172274/c1267b8a-24f0-11e7-8130-af551a8a958d.png)

   GUI 下半部分参数（biases，偏置）的修改指南见：https://inivation.github.io/inivation-docs/Advanced%20configurations/User_guide_-_Biasing.html


# 标定

关于 DVS 和 DAVIS 的内参标定或双目标定，请查看以下[文档](dvs_calibration/README.md)。


# 故障排查

## 新的 dvs_msgs 格式

如果你使用本软件包旧版本录制过 rosbag，则这些 bag 必须迁移。
时间戳格式已经从 uint64 改为 rostime。
要转换一个“旧” bag 文件，请使用：
`$ rosbag fix old.bag new.bag`。

## 编译错误

在使用 GCC 4.8 的 Ubuntu 14.04 上，你会遇到缺少文件（`stdatomic.h`）的错误。
这是一个与 GCC 4.8 相关的[问题](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=58016)，可以通过[更新到 4.9 版本](http://askubuntu.com/a/581497/218846)解决：

    sudo add-apt-repository ppa:ubuntu-toolchain-r/test
    sudo apt-get update
    sudo apt-get install gcc-4.9 g++-4.9
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.9 60 --slave /usr/bin/g++ g++ /usr/bin/g++-4.9
