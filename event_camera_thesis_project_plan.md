# 事件相机本科毕业论文项目梳理与当前任务计划

> 文件用途：作为当前毕业论文项目的主线说明、阶段计划和本周执行清单。  
> 当前阶段重点：**先把 DAVIS346 在 Docker + ROS 环境中稳定跑通。**

---

## 1. 项目一句话定义

本项目的核心不是“把某一台事件相机接上电脑”，而是：

> **选择一个事件相机算法，在多种不同型号的事件相机上进行统一测试和对比，分析不同硬件平台对算法表现的影响。**

后期如果条件允许，还可能继续扩展：

> **使用较新的事件相机自行采集数据，制作数据集，并尝试形成可发表的实验结果。**

---

# 2. 整个毕业论文的主线

目前可以把整个项目分成四个阶段。

## 阶段 A：硬件和软件环境跑通

目标：

- 学会使用事件相机
- 建立稳定的软件环境
- 让 ROS 能识别相机
- 能够获取事件数据
- 能够记录数据
- 熟悉不同相机的数据接口

当前你就在这个阶段。

现在老师给了你：

- 两台 DAVIS346
- 一个用于 DAVIS346 的 ROS 驱动 GitHub 项目
- 一个明确任务：先把相机连通并跑起来

这一阶段暂时不追求算法结果。

---

## 阶段 B：统一算法测试框架

目标：

选择一个事件相机算法，并建立统一实验框架。

例如：

```text
                 同一个算法
                     |
        -----------------------------
        |           |          |    |
      Camera A   Camera B   Camera C Camera D
        |           |          |    |
        -----------------------------
                     |
                 对比结果
```

后续可能测试约四种不同型号的事件相机。

比较内容可能包括：

- 算法准确率
- 延迟
- Event Rate
- 噪声
- 时间分辨率
- 空间分辨率
- 数据质量
- CPU / GPU 消耗
- 算法稳定性
- 不同场景表现

真正的论文实验，大概率主要发生在这一阶段。

---

## 阶段 C：多型号事件相机对比

这一阶段需要解决一个重要问题：

> 不同事件相机产生的数据格式、分辨率、时间戳、噪声特性可能不同。

因此不能简单地：

```text
换一个相机
↓
直接运行算法
↓
比较结果
```

而应该建立一个统一的数据处理流程：

```text
不同事件相机
       |
       v
数据读取 / ROS Driver
       |
       v
数据格式统一
       |
       v
预处理
       |
       v
同一个算法
       |
       v
统一指标评价
```

这一部分很可能成为论文中比较有价值的工程内容。

---

## 阶段 D：自行采集数据集

这是后期扩展方向。

如果前面的系统稳定，可能会使用新的事件相机自行采集数据集。

基本流程：

```text
实验设计
  |
  v
相机配置
  |
  v
时间同步
  |
  v
数据采集
  |
  v
数据清洗
  |
  v
标注
  |
  v
数据格式整理
  |
  v
Dataset
  |
  v
算法实验
```

如果数据集有价值、实验设计合理，这部分才有可能进一步形成论文或发表成果。

---

# 3. 当前真正应该关注什么

## 当前不要把注意力放在整个毕业论文上

现在最重要的事情只有一个：

> **把 DAVIS346 稳定跑起来。**

不要同时处理：

- 四台相机
- 多机同步
- 数据集制作
- 最终算法
- 论文写作
- 发表

这些以后再做。

当前阶段需要建立第一条完整链路：

```text
DAVIS346
   |
   | USB
   v
Ubuntu Host
   |
   v
Docker
   |
   v
Ubuntu 20.04
   |
   v
ROS1
   |
   v
DAVIS ROS Driver
   |
   v
ROS Topic
   |
   v
Event Data
```

只要这一条链真正跑通，后面的事情才有基础。

---

# 4. 为什么现在需要 Docker

你的宿主系统比较新。

当前情况可以理解成：

```text
Host
Ubuntu 26.x
```

但老师给你的 ROS 项目属于较旧的软件栈。

它可能依赖：

```text
Ubuntu 20.04
+
ROS Noetic
+
旧版依赖
+
DAVIS Driver
```

直接把老 ROS 项目安装到新系统里，容易出现：

- ROS 版本不兼容
- Python 版本不兼容
- CMake 版本差异
- Eigen / OpenCV 版本问题
- libcaer 版本冲突
- catkin 编译问题
- ROS package 缺失
- 系统库 ABI 不兼容

因此 Docker 的作用是：

> **在你的 Ubuntu 26 系统中创建一个相对独立的 Ubuntu 20.04 + ROS 环境。**

可以把它想成：

```text
Ubuntu 26 Host
|
+-- Docker Container
       |
       +-- Ubuntu 20.04
       |
       +-- ROS Noetic
       |
       +-- DAVIS Driver
```

这样不用为了运行旧项目去破坏宿主系统。

---

# 5. Docker 在这里最大的难点

普通软件跑在 Docker 中通常比较直接。

但你现在需要访问：

> **真实 USB 硬件：DAVIS346**

因此问题会多一层。

完整链路是：

```text
DAVIS346
   |
   | USB
   v
Linux Kernel
   |
   v
/dev/bus/usb
   |
   v
Docker Container
   |
   v
libusb / libcaer
   |
   v
ROS Driver
```

所以 Docker 是否成功，不只是看：

```bash
roscore
```

能不能运行。

还必须确认：

> Docker 容器能不能看到 DAVIS346。

---

# 6. 老师给的 GitHub 项目

当前老师给出的 GitHub 项目已确认为：

```text
https://github.com/uzh-rpg/rpg_dvs_ros
```

这是一套较老的 ROS1 事件相机软件栈。

它与 DAVIS / DVS 相机有关。

当前应以这个仓库作为 DAVIS346 跑通阶段的主项目。

仓库基本信息：

- Repository：`uzh-rpg/rpg_dvs_ros`
- URL：`https://github.com/uzh-rpg/rpg_dvs_ros`
- 默认分支：`master`
- 支持环境：ROS Kinetic / Melodic / Noetic
- 对应系统：Ubuntu 16.04 / 18.04 / 20.04
- 当前推荐组合：Ubuntu 20.04 + ROS Noetic
- DAVIS 相机对应编译目标：`davis_ros_driver`
- 主要依赖：`libcaer-dev`、`catkin_simple`、`python3-catkin-tools`、ROS camera/image 相关包

其中可能涉及：

- DAVIS ROS Driver
- Event Message
- ROS Topic
- 数据录制
- Event Camera 工具

---

# 7. 当前系统的软件层次

建议脑子里始终保持下面这个结构。

```text
ROS Node
   |
   v
DAVIS ROS Driver
   |
   v
libcaer / camera library
   |
   v
libusb
   |
   v
Linux USB
   |
   v
DAVIS346
```

几个东西不要混：

## ROS

负责：

- Node
- Topic
- Message
- 数据流
- rosbag

ROS 本身不是 DAVIS346 的底层驱动。

---

## DAVIS ROS Driver

作用：

> 把相机数据转换成 ROS 可以使用的数据。

---

## libcaer

作用更靠近设备。

可以理解为：

> 与事件相机硬件通信的软件库。

---

## libusb

负责 Linux 用户空间程序与 USB 设备通信。

---

## Linux Kernel

真正管理 USB 设备。

---

# 8. 本周任务

这一周建议只设一个总目标：

> **在 Docker 中运行 DAVIS346 ROS Driver，并成功获取相机数据。**

不要把目标写成：

> 学习 Docker。

也不要写成：

> 学习 ROS。

这些只是工具。

真正的验收结果必须是：

> **DAVIS346 → Docker → ROS → Event Topic 跑通。**

---

# 9. 本周任务拆解

## Task 1：确认硬件在宿主 Ubuntu 中可见

先不要碰 Docker。

连接一台 DAVIS346。

在宿主机确认 USB 设备存在。

例如：

```bash
lsusb
```

如果宿主机都看不到相机，Docker 更不可能看到。

### 验收标准

宿主 Ubuntu 能识别 DAVIS346 USB 设备。

---

## Task 2：确认老师给的 GitHub 仓库

记录：

- GitHub URL
- Branch
- README
- ROS 版本
- Ubuntu 版本
- 依赖
- 编译方式
- 是否需要 libcaer
- 是否有 DAVIS346 示例命令

不要一开始就乱装包。

先确认项目要求什么环境。

### 验收标准

至少能回答：

```text
这个项目要求：
Ubuntu = ?
ROS = ?
Python = ?
libcaer = ?
Build System = catkin / catkin_tools / ?
```

---

## Task 3：建立 Ubuntu 20.04 Docker 环境

目标：

创建一个能长期复用的开发容器。

推荐结构：

```text
Dockerfile
docker-compose.yml
catkin_ws/
README.md
```

不要长期靠一条巨长的：

```bash
docker run ...
```

手动启动。

后期参数越来越多以后很难维护。

---

## Task 4：在 Docker 中安装 ROS

如果仓库确实要求 Ubuntu 20.04 + ROS1，那么通常对应：

```text
Ubuntu 20.04
ROS Noetic
```

完成后至少测试：

```bash
roscore
```

能够正常启动。

### 验收标准

Docker 内 ROS 环境正常。

---

## Task 5：把 GitHub 项目放进 catkin workspace

典型目录结构：

```text
~/catkin_ws/
|
+-- src/
|    |
|    +-- rpg_dvs_ros/
|
+-- build/
+-- devel/
```

然后按照仓库 README 安装依赖。

可能涉及：

```bash
rosdep
catkin_make
```

或：

```bash
catkin build
```

具体以仓库要求为准。

---

## Task 6：解决编译问题

这里很可能是本周最耗时间的部分。

每出现一个错误，都要记录。

不要采取：

```text
报错
↓
Google
↓
复制命令
↓
又报错
↓
再复制
```

这种方式。

推荐记录：

```text
Error:
...

Cause:
...

Solution:
...

Result:
...
```

以后第二台电脑或第二个容器可以直接复现。

---

# 10. Docker 访问 DAVIS346

这是当前最关键的 Docker 问题。

容器启动时，需要把 USB 设备暴露给 Docker。

常见方式之一是映射：

```text
/dev/bus/usb
```

概念上类似：

```bash
docker run \
  --device=/dev/bus/usb \
  ...
```

实际参数需要根据 Docker 和设备情况调整。

调试早期也可能临时使用更宽松的权限模式。

但是：

> `--privileged`

适合排错，不建议长期作为最终方案。

最终应该尽量明确：

- USB Device
- udev rule
- 用户权限
- device mapping

---

# 11. Docker 内第一项硬件测试

进入 Docker 后运行：

```bash
lsusb
```

必须看到 DAVIS346。

这是一个非常重要的分界点。

---

## 情况 A

宿主机：

```text
DAVIS visible
```

Docker：

```text
DAVIS visible
```

说明 USB passthrough 基本成功。

接下来检查相机库和 ROS Driver。

---

## 情况 B

宿主机：

```text
DAVIS visible
```

Docker：

```text
DAVIS NOT visible
```

问题基本就在：

- Docker device mapping
- permissions
- udev
- container privilege

不要去改 ROS。

---

## 情况 C

宿主机本身：

```text
DAVIS NOT visible
```

先检查：

- USB 线
- USB 接口
- 相机供电
- Linux USB
- 硬件状态

此时 Docker 和 ROS 都不是重点。

---

# 12. ROS Driver 启动后的验证

Driver 成功启动并不等于任务完成。

必须继续检查 ROS 数据。

先查看：

```bash
rostopic list
```

目标是出现 DAVIS 相关 Topic。

可能包括：

```text
/events
/imu
/image_raw
/camera_info
...
```

具体名称由 Driver 决定。

---

然后检查：

```bash
rostopic hz <event_topic>
```

确认事件数据持续产生。

---

如果有合适工具，还可以进一步观察：

- Event Stream
- APS Frame
- IMU
- Camera Info

---

# 13. 当前阶段 Definition of Done

只有满足下面这些条件，才能认为：

> “DAVIS346 已经跑通。”

## Level 1：Host

- [ ] DAVIS346 接入电脑
- [ ] `lsusb` 能看到设备

## Level 2：Docker

- [ ] Ubuntu 20.04 Container 能启动
- [ ] Docker 内 `lsusb` 能看到 DAVIS346

## Level 3：ROS

- [ ] ROS 环境正常
- [ ] `roscore` 能运行

## Level 4：Driver

- [ ] GitHub 项目成功编译
- [ ] DAVIS Driver 能启动
- [ ] Driver 能识别 DAVIS346

## Level 5：Data

- [ ] `rostopic list` 能看到 Event Topic
- [ ] Event Topic 有持续数据
- [ ] 移动相机时 Event Rate 明显变化

## Level 6：Recording

- [ ] 能使用 rosbag 或对应工具录制数据
- [ ] 能重新读取录制的数据

完成 Level 6 后，第一阶段才算真正结束。

---

# 14. 建议的本周执行顺序

不要同时做很多事情。

严格按照下面顺序：

```text
1. DAVIS 插到 Ubuntu
        |
        v
2. Host lsusb
        |
        v
3. 确认 GitHub README
        |
        v
4. 建 Ubuntu20 Docker
        |
        v
5. 安装 ROS
        |
        v
6. Docker lsusb
        |
        v
7. clone ROS Driver
        |
        v
8. 安装依赖
        |
        v
9. 编译
        |
        v
10. 启动 Driver
        |
        v
11. rostopic list
        |
        v
12. Event 数据验证
        |
        v
13. rosbag 录制
```

每一步成功以后再继续。

不要跨步骤。

---

# 15. 推荐的工作目录

建议在宿主机建立统一项目目录。

例如：

```text
event_camera_thesis/
|
+-- docker/
|    |
|    +-- Dockerfile
|    +-- docker-compose.yml
|
+-- catkin_ws/
|    |
|    +-- src/
|
+-- data/
|    |
|    +-- raw/
|    +-- test/
|
+-- logs/
|
+-- docs/
|    |
|    +-- project_plan.md
|    +-- setup_notes.md
|    +-- troubleshooting.md
|
+-- scripts/
```

不要把东西散落在：

```text
Downloads/
Desktop/
test/
test2/
final/
final2/
```

项目一旦进入四台相机阶段，这种目录会迅速失控。

---

# 16. 从现在开始建立实验日志

建议每天至少记录：

```markdown
## Date

2026-08-12

## Goal

Docker 中识别 DAVIS346

## Environment

Host:
Ubuntu 26.x

Container:
Ubuntu 20.04

ROS:
Noetic

Camera:
DAVIS346 #1

## Commands

...

## Result

...

## Error

...

## Solution

...

## Next Step

...
```

目的不是写日记。

目的是：

> 三个月以后依然可以完整复现今天的环境。

---

# 17. 两台 DAVIS346 现在怎么用

目前不要急着双相机同步。

建议：

## 第一步

只连接：

```text
DAVIS346 #1
```

把整个 ROS 链路跑通。

---

## 第二步

换成：

```text
DAVIS346 #2
```

验证同一个环境也能识别第二台。

---

## 第三步

再考虑：

```text
DAVIS346 #1
+
DAVIS346 #2
```

同时运行。

双机阶段才会开始遇到：

- Serial Number
- Device Selection
- ROS Namespace
- Topic Naming
- USB Bandwidth
- Timestamp
- Hardware Synchronization

这些不是本周第一优先级。

---

# 18. 后续为什么会涉及时间同步

等你测试不同型号的事件相机以后，多机同步可能成为重要问题。

Event 数据通常包含：

```text
(x, y, t, polarity)
```

其中：

```text
t = timestamp
```

如果两个相机使用不同内部时钟：

```text
Camera A clock
Camera B clock
```

那么：

```text
t_A
```

和：

```text
t_B
```

不一定属于同一时间基准。

后面可能需要研究：

- Hardware Trigger
- External Clock
- Master / Slave
- PPS
- Timestamp Offset
- Clock Drift
- Jitter

但这些属于后续阶段。

当前先不要因为同步问题耽误第一台相机跑通。

---

# 19. 当前阶段最容易犯的错误

## 错误 1：一开始就研究算法

现在连稳定数据流都没有。

先不要跑算法。

---

## 错误 2：一开始就接两台相机

变量太多。

第一台先跑通。

---

## 错误 3：Docker、ROS、Driver、USB 一起调

出现错误以后无法定位问题在哪一层。

应该分层验证。

---

## 错误 4：只看 Driver 有没有启动

Driver 打印：

```text
started successfully
```

并不能证明事件数据真的正常。

必须检查 Topic 和数据频率。

---

## 错误 5：环境调通以后不保存

一定要保留：

```text
Dockerfile
docker-compose.yml
requirements
Git commit
README
```

否则下次重新安装又从头开始。

---

# 20. 本周最低目标

如果时间比较紧，本周最低完成：

- [ ] Host 能识别 DAVIS346
- [ ] Docker Ubuntu20 环境建立
- [ ] Docker 能访问 DAVIS346
- [ ] ROS 能运行
- [ ] ROS Driver 能编译

---

# 21. 本周理想目标

最好完成：

- [ ] DAVIS346 Driver 成功启动
- [ ] ROS 能获取 Event Topic
- [ ] Event 数据能够实时产生
- [ ] 能录制一小段 rosbag
- [ ] 能重新播放数据
- [ ] 整个环境写进 Dockerfile / Compose
- [ ] 留下一份完整安装记录

如果做到这里，本周任务非常成功。

---

# 22. 当前项目的优先级

可以直接记住：

```text
Priority 1
DAVIS346 跑通
       |
       v
Priority 2
稳定记录数据
       |
       v
Priority 3
第二台 DAVIS346
       |
       v
Priority 4
其他型号 Event Camera
       |
       v
Priority 5
统一算法
       |
       v
Priority 6
Benchmark
       |
       v
Priority 7
自行采集 Dataset
       |
       v
Priority 8
Publication
```

现在只盯住 Priority 1。

---

# 23. 下一次实际操作时建议从哪里开始

下一次打开电脑以后，不需要先研究论文。

直接从下面开始：

```bash
lsusb
```

确认 DAVIS346。

然后确认老师提供的 GitHub Repository。

接下来开始建立：

```text
Ubuntu 20.04 Docker
+
ROS Noetic
+
DAVIS Driver
```

整个过程中，一次只解决一层问题。

---

# 24. 当前项目的核心判断

目前这个阶段的成功标准不是：

> “我理解事件相机了。”

也不是：

> “Docker 装好了。”

而是：

> **我能把 DAVIS346 插进电脑，在 Docker 里的 ROS Driver 中识别它，并稳定接收到 Event Data。**

只要这件事情完成，你的毕业论文工程基础就真正建立起来了。

---

# 25. 当前任务看板

## TODO

- [x] 找到老师发的 GitHub Repository：`https://github.com/uzh-rpg/rpg_dvs_ros`
- [x] 保存 Repository URL
- [x] 阅读 README
- [x] 确认 Ubuntu / ROS 版本：Ubuntu 20.04 + ROS Noetic
- [ ] DAVIS346 接入电脑
- [ ] Host `lsusb`
- [ ] 建立 Ubuntu20 Docker
- [ ] Docker 内安装 ROS
- [ ] Docker USB passthrough
- [ ] Docker `lsusb`
- [ ] Clone Repository
- [ ] 安装依赖
- [ ] 编译 Workspace
- [ ] 启动 Driver
- [ ] `rostopic list`
- [ ] 检查 Event Topic
- [ ] 检查 Event Rate
- [ ] 录制测试数据
- [ ] 保存 Docker 环境
- [ ] 编写 Setup Notes

---

## 当前状态

```text
项目阶段：
Hardware / Software Bring-up

当前设备：
DAVIS346 × 2

当前主要设备：
DAVIS346 #1

当前主要任务：
Docker + ROS + DAVIS Driver

当前目标：
获得稳定 Event Stream
```

---

# 26. 最终总结

你的毕业论文不是一个单纯的：

> “DAVIS346 使用教程。”

DAVIS346 只是当前的第一块实验硬件。

真正的论文主线是：

```text
多个 Event Camera
        |
        v
统一算法
        |
        v
统一测试
        |
        v
性能对比
        |
        v
分析硬件差异
```

后期再考虑：

```text
新型 Event Camera
        |
        v
自行采集
        |
        v
Dataset
        |
        v
更完整的实验
        |
        v
潜在发表
```

而你现在需要做的事情非常具体：

> **先把一台 DAVIS346 在 Ubuntu 20.04 Docker + ROS 环境中稳定跑通。**

这是当前最重要的里程碑。
