#include <algorithm>
#include <memory>
#include <string>

#include <camera_info_manager/camera_info_manager.h>
#include <dvs_msgs/Event.h>
#include <dvs_msgs/EventArray.h>
#include <prophesee_event_msgs/EventArray.h>
#include <ros/ros.h>
#include <sensor_msgs/CameraInfo.h>

namespace {

bool matrixIsZero(const boost::array<double, 9> &matrix) {
  return std::all_of(matrix.begin(), matrix.end(), [](double value) { return value == 0.0; });
}

bool matrixIsZero(const boost::array<double, 12> &matrix) {
  return std::all_of(matrix.begin(), matrix.end(), [](double value) { return value == 0.0; });
}

void completeProjectionMatrices(sensor_msgs::CameraInfo *info) {
  if (matrixIsZero(info->R)) {
    info->R[0] = 1.0;
    info->R[4] = 1.0;
    info->R[8] = 1.0;
  }
  if (matrixIsZero(info->P) && !matrixIsZero(info->K)) {
    info->P[0] = info->K[0];
    info->P[2] = info->K[2];
    info->P[5] = info->K[4];
    info->P[6] = info->K[5];
    info->P[10] = 1.0;
  }
}

class PropheseeEventAdapter {
 public:
  PropheseeEventAdapter() : nh_(), pnh_("~"), width_(0), height_(0) {
    pnh_.param<std::string>("source_events_topic", source_events_topic_,
                            "/prophesee/camera/cd_events_buffer");
    pnh_.param<std::string>("source_camera_info_topic", source_camera_info_topic_,
                            "/prophesee/camera/camera_info");
    pnh_.param<std::string>("frame_id", frame_id_, "event_camera_optical_frame");
    pnh_.param<std::string>("camera_name", camera_name_, "prophesee_event_camera");
    pnh_.param<std::string>("camera_info_url", camera_info_url_, "");

    camera_info_manager_.reset(
        new camera_info_manager::CameraInfoManager(nh_, camera_name_, camera_info_url_));

    event_pub_ = nh_.advertise<dvs_msgs::EventArray>("events", 1000);
    camera_info_pub_ = nh_.advertise<sensor_msgs::CameraInfo>("camera_info", 10);

    event_sub_ = nh_.subscribe(source_events_topic_, 1000,
                               &PropheseeEventAdapter::eventsCallback, this,
                               ros::TransportHints().tcpNoDelay());
    source_camera_info_sub_ =
        nh_.subscribe(source_camera_info_topic_, 10,
                      &PropheseeEventAdapter::sourceCameraInfoCallback, this);

    double camera_info_rate = 5.0;
    pnh_.param("camera_info_rate", camera_info_rate, camera_info_rate);
    camera_info_timer_ = nh_.createTimer(ros::Duration(1.0 / camera_info_rate),
                                         &PropheseeEventAdapter::publishCameraInfo, this);

    ROS_INFO_STREAM("Prophesee adapter: " << source_events_topic_ << " -> "
                                           << nh_.resolveName("events"));
    ROS_INFO_STREAM("CameraInfo URL: "
                    << (camera_info_url_.empty() ? "<none>" : camera_info_url_));
  }

 private:
  void eventsCallback(const prophesee_event_msgs::EventArray::ConstPtr &input) {
    dvs_msgs::EventArray output;
    output.header = input->header;
    output.header.frame_id = frame_id_;
    output.width = input->width;
    output.height = input->height;
    output.events.resize(input->events.size());

    for (std::size_t index = 0; index < input->events.size(); ++index) {
      const auto &source = input->events[index];
      auto &target = output.events[index];
      target.x = source.x;
      target.y = source.y;
      target.ts = source.ts;
      target.polarity = source.polarity;
    }

    width_ = input->width;
    height_ = input->height;
    last_stamp_ = input->header.stamp;
    event_pub_.publish(output);
  }

  void sourceCameraInfoCallback(const sensor_msgs::CameraInfo::ConstPtr &input) {
    if (input->width > 0 && input->height > 0) {
      width_ = input->width;
      height_ = input->height;
    }
    if (!input->header.stamp.isZero()) {
      last_stamp_ = input->header.stamp;
    }
  }

  void publishCameraInfo(const ros::TimerEvent &) {
    if (width_ == 0 || height_ == 0 || camera_info_pub_.getNumSubscribers() == 0) {
      return;
    }

    sensor_msgs::CameraInfo info = camera_info_manager_->getCameraInfo();
    if (info.width != 0 && info.height != 0 &&
        (info.width != width_ || info.height != height_)) {
      ROS_ERROR_THROTTLE(5.0,
                         "Ignoring calibration with resolution %ux%u for %ux%u event stream",
                         info.width, info.height, width_, height_);
      info = sensor_msgs::CameraInfo();
    }
    if (info.width == 0 || info.height == 0) {
      info.width = width_;
      info.height = height_;
    }
    info.header.frame_id = frame_id_;
    info.header.stamp = last_stamp_.isZero() ? ros::Time::now() : last_stamp_;
    completeProjectionMatrices(&info);
    camera_info_pub_.publish(info);
  }

  ros::NodeHandle nh_;
  ros::NodeHandle pnh_;
  ros::Publisher event_pub_;
  ros::Publisher camera_info_pub_;
  ros::Subscriber event_sub_;
  ros::Subscriber source_camera_info_sub_;
  ros::Timer camera_info_timer_;
  std::unique_ptr<camera_info_manager::CameraInfoManager> camera_info_manager_;
  std::string source_events_topic_;
  std::string source_camera_info_topic_;
  std::string frame_id_;
  std::string camera_name_;
  std::string camera_info_url_;
  uint32_t width_;
  uint32_t height_;
  ros::Time last_stamp_;
};

}  // namespace

int main(int argc, char **argv) {
  ros::init(argc, argv, "prophesee_event_adapter");
  PropheseeEventAdapter adapter;
  ros::spin();
  return 0;
}
