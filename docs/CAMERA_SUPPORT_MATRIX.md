# 相机支持矩阵

| 相机 | 单目 | 双目 | GUI | 数据 | 标定 | 真机状态 |
| --- | --- | --- | --- | --- | --- | --- |
| DAVIS | 支持 | 支持；serial 可选 | renderer + rqt | rosbag | APS 棋盘格；LED 入口 | 单目、双目已验证 |
| DVXplorer | 支持 | 支持；serial 可选 | renderer + rqt | rosbag | LED 双目标定入口 | 待真机验证 |
| Prophesee EVK4-HD | 支持 | 支持；双目必须 serial | 官方单目 Viewer；双目 renderer + rqt | OpenEB RAW + rosbag | LED 单/双目入口 | 单目已验证；双目待验证 |
| Prophesee EVK1-VGA | 支持 | 支持；双目必须 serial | renderer + rqt | OpenEB RAW + rosbag | LED 单/双目入口 | 单目已验证；双目待验证 |

## 固定约束

| 项目 | 约束 |
| --- | --- |
| EVK1 型号 | 仅 EVK1 Gen3/Gen3.1 VGA `640×480`，OpenEB `system_ID` `21/28`；不声明 EVK1-HD |
| EVK4 型号 | IMX636 `1280×720`，OpenEB `system_ID` `49` |
| EVK1 SDK | OpenEB `3.1.2`，commit `04022c2f1dac338d4dc6ec85d50fcfafd74f9989` |
| EVK4 SDK | OpenEB `4.6.2`，commit `53b3618935f90dcc0f64993ccbb79514384404b0` |
| ROS | Ubuntu 20.04 + ROS Noetic |
| 统一事件接口 | `dvs_msgs/EventArray`；EVK4 单目原生接口默认保留，适配器可选 |
| Prophesee 双目 | 必须提供两个不同 serial；同步精度在真机测量前保持未验证 |
| 论文范围 | 单目与双目实验均为必做；数据集制作细节待实验协议确定 |
