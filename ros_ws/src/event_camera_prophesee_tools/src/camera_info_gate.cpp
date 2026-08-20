#include <algorithm>
#include <cmath>

#include <ros/ros.h>
#include <sensor_msgs/CameraInfo.h>

namespace {

bool isValidCalibration(const sensor_msgs::CameraInfo &info) {
  return info.width > 0 && info.height > 0 && info.D.size() >= 5 &&
         std::isfinite(info.K[0]) && std::isfinite(info.K[4]) &&
         info.K[0] > 0.0 && info.K[4] > 0.0 &&
         std::all_of(info.D.begin(), info.D.begin() + 5,
                     [](double value) { return std::isfinite(value); });
}

class CameraInfoGate {
 public:
  CameraInfoGate() : nh_(), pnh_("~") {
    pnh_.param("warn_on_invalid", warn_on_invalid_, true);
    publisher_ = nh_.advertise<sensor_msgs::CameraInfo>("output", 1, true);
    subscriber_ = nh_.subscribe("input", 1, &CameraInfoGate::callback, this);
  }

 private:
  void callback(const sensor_msgs::CameraInfo::ConstPtr &message) {
    if (isValidCalibration(*message)) {
      publisher_.publish(message);
      return;
    }
    if (warn_on_invalid_) {
      ROS_WARN_THROTTLE(
          5.0,
          "CameraInfo has no valid K/D calibration; withholding it from dvs_calibration");
    }
  }

  ros::NodeHandle nh_;
  ros::NodeHandle pnh_;
  ros::Publisher publisher_;
  ros::Subscriber subscriber_;
  bool warn_on_invalid_;
};

}  // namespace

int main(int argc, char **argv) {
  ros::init(argc, argv, "camera_info_gate");
  CameraInfoGate gate;
  ros::spin();
  return 0;
}
