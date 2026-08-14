# DAVIS 标定

对于 DAVIS，我们建议使用帧图像进行内参标定。
更多细节可以参考 ROS Wiki 中的[单目标定](http://wiki.ros.org/camera_calibration/Tutorials/MonocularCalibration)和[双目标定](http://wiki.ros.org/camera_calibration/Tutorials/StereoCalibration)教程。

# DVS 标定

DVS 的标定是一个两阶段过程。
首先，需要调整焦距。
然后，估计相机内参。

## 焦距调整

调整 DVS 的焦距。实现这一点的一种方式是使用特殊图案，例如 [Back Focus Pattern](https://github.com/uzh-rpg/rpg_dvs_ros/blob/master/dvs_calibration/pdf/backfocus.pdf)。

## 内参

运行内参相机标定时，我们使用一个以 500Hz 闪烁的 5x5 LED 板。
标定流程通过以下命令启动：
`$ roslaunch dvs_calibration dvs_intrinsic.launch`
你会看到一个包含所有必要信息的 RQT 界面。
左上角是标定 GUI，会显示检测到的图案数量。
**目前，图案检测在室内似乎无法正常工作。可以尝试靠近窗户的位置。**
开始标定前至少采集 30 个样本。
**这可能需要几分钟时间**，并且会使 RQT GUI 暂时卡住。
完成后，标定参数会显示出来，并且可以保存。
相机参数会存储在 `~/.ros/camera_info`。
当你再次插入这台 DVS 时，该标定文件会被加载，并作为 `/dvs/camera_info` 发布。

下面的图像查看器显示以下内容：

1. 累积的 DVS 渲染结果：你应该能看到闪烁的 LED 和场景中的梯度
2. 检测到的闪烁：黑色区域表示更多检测结果。图案一旦被检测到，标定 GUI 中的计数器应该会增加。检测到的图案也会短暂可视化显示。
3. 校正后的 DVS 渲染结果：标定完成后，你可以观察标定效果。检查直线是否仍然保持为直线，尤其是图像边缘区域。


# 双目 DVS 标定

## 设置

将两台 DVS 从 OUT（master，主设备）连接到 IN（slave，从设备）。
如果两台 DVS 都通过 USB 连接到同一台电脑，为避免地环路，不应连接 GND。
时间同步会在驱动软件中自动完成。
由于每台 DVS 都有独立驱动，ROS 消息可能会在不同时间到达。
但是，消息内部的时间戳是同步的。

## 标定

1. 分别独立标定每台 DVS
2. 使用 `$ roslaunch dvs_calibration dvs_stereo.launch`
3. 使用同一个带闪烁 LED 的棋盘，并确保两台相机都能看到它。至少采集 30 个样本。
4. 启动标定并检查重投影误差。然后保存结果（这会把双目信息追加到你的内参相机信息文件中）。


# 标定细节与参数

标定需要一个由闪烁 LED 组成的规则网格板。
在我们的配置中，使用的是 5x5 网格，LED 间距为 0.05m。
其中一行可以关闭（变成 5x4 网格），以避免双目标定时产生混淆。
以下参数可以通过 ROS 参数调节：

* `dots_w`, `dots_h`（默认值：5）表示 LED 网格中的行数和列数
* `dot_distance`（默认值：0.05）表示 LED 之间的距离，单位为**米**

如果你使用自己的 LED 板，并且 LED 或闪烁频率不同，也可能需要调整这些参数：

* `blinking_time_us`（默认值：1000）表示闪烁时间，单位为**微秒**
* `blinking_time_tolerance_us`（默认值：500）表示仍然计为一次跳变的时间容差，单位为**微秒**
* `enough_transitions_threshold`（默认值：200）表示开始搜索 LED 之前所需的最小跳变数量
* `minimum_transitions_threshold`（默认值：10）表示在 LED 搜索中被纳入考虑所需的最小跳变数量
* `minimum_led_mass`（默认值：50）表示一个 LED blob 的最小“质量”，也就是该 blob 中跳变数量的总和
* `pattern_search_timeout`（默认值：2.0）表示重置 transition map 的超时时间，单位为**秒**（找到 LED 网格时也会重置）
