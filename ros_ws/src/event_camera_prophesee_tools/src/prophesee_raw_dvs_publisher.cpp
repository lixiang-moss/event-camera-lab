#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <camera_info_manager/camera_info_manager.h>
#include <dvs_msgs/EventArray.h>
#include <event_camera_msgs/ExternalTriggerArray.h>
#include <metavision/sdk/base/events/event_cd.h>
#include <metavision/sdk/base/events/event_ext_trigger.h>
#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <ros/ros.h>
#include <sensor_msgs/CameraInfo.h>

#include "event_camera_prophesee_tools/openeb_compat.h"

namespace {

class RawDvsPublisher {
 public:
  RawDvsPublisher()
      : nh_(), pnh_("~"), sequence_(0), runtime_error_(false) {
    pnh_.param<std::string>("raw_file_to_read", raw_file_, "");
    pnh_.param<std::string>("frame_id", frame_id_, "event_camera_optical_frame");
    pnh_.param<std::string>("camera_name", camera_name_, "");
    pnh_.param<std::string>("camera_info_url", camera_info_url_, "");
    pnh_.param("realtime", realtime_, true);
    pnh_.param("timestamp_offset_sec", timestamp_offset_sec_, 0.0);
    pnh_.param("timestamp_base_us", timestamp_base_us_, 0.0);
    double event_delta_t = 0.001;
    pnh_.param("event_delta_t", event_delta_t, event_delta_t);
    pnh_.param("subscriber_wait_timeout", subscriber_wait_timeout_, 5.0);
    event_delta_us_ = std::max<std::int64_t>(1, std::llround(event_delta_t * 1e6));
    if (raw_file_.empty()) {
      throw std::runtime_error("~raw_file_to_read is required");
    }
    if (timestamp_offset_sec_ <= 0.0) {
      timestamp_offset_sec_ = ros::Time::now().toSec();
    }

    camera_.reset(new Metavision::Camera(
        event_camera_prophesee_tools::openRawFile(raw_file_, false, false)));
    const auto config = camera_->get_camera_configuration();
    serial_ = event_camera_prophesee_tools::cameraSerial(camera_.get());
    if (camera_name_.empty()) {
      camera_name_ = "prophesee_" + serial_;
    }
    if (camera_info_url_.empty()) {
      camera_info_url_ = "file:///root/.ros/camera_info/prophesee_" + serial_ + ".yaml";
    }
    camera_info_manager_.reset(
        new camera_info_manager::CameraInfoManager(nh_, camera_name_, camera_info_url_));

    events_pub_ = nh_.advertise<dvs_msgs::EventArray>("events", 1000);
    camera_info_pub_ = nh_.advertise<sensor_msgs::CameraInfo>("camera_info", 10, true);
    trigger_pub_ = nh_.advertise<event_camera_msgs::ExternalTriggerArray>("ext_trigger", 100);

    camera_->cd().add_callback(
        [this](const Metavision::EventCD *begin, const Metavision::EventCD *end) {
          eventsCallback(begin, end);
        });
    camera_->ext_trigger().add_callback(
        [this](const Metavision::EventExtTrigger *begin,
               const Metavision::EventExtTrigger *end) {
          triggerCallback(begin, end);
        });
    camera_->add_runtime_error_callback([this](const Metavision::CameraException &error) {
      ROS_ERROR_STREAM("RAW playback error: " << error.what());
      runtime_error_.store(true);
    });
    pnh_.setParam("selected_serial", serial_);
    pnh_.setParam("event_delta_t", static_cast<double>(event_delta_us_) / 1e6);
  }

  int run() {
    const ros::WallTime deadline =
        ros::WallTime::now() + ros::WallDuration(subscriber_wait_timeout_);
    while (ros::ok() && events_pub_.getNumSubscribers() == 0 &&
           ros::WallTime::now() < deadline) {
      ros::spinOnce();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    publishCameraInfo(ros::Time::now());
    if (!camera_->start()) {
      ROS_ERROR("Failed to start RAW playback");
      return 2;
    }
    ros::WallRate rate(200);
    while (ros::ok() && camera_->is_running() && !runtime_error_.load()) {
      ros::spinOnce();
      rate.sleep();
    }
    camera_->stop();
    flushEvents();
    ros::WallDuration(0.25).sleep();
    return runtime_error_.load() ? 3 : 0;
  }

 private:
  ros::Time mappedTime(Metavision::timestamp timestamp_us) const {
    const double relative_sec =
        (static_cast<double>(timestamp_us) - timestamp_base_us_) / 1e6;
    return ros::Time(timestamp_offset_sec_) + ros::Duration(relative_sec);
  }

  void waitUntil(const ros::Time &target) const {
    if (!realtime_) {
      return;
    }
    const double delay = target.toSec() - ros::WallTime::now().toSec();
    if (delay > 0.0) {
      ros::WallDuration(delay).sleep();
    }
  }

  void eventsCallback(const Metavision::EventCD *begin,
                      const Metavision::EventCD *end) {
    std::lock_guard<std::mutex> lock(event_mutex_);
    for (const auto *event = begin; event != end; ++event) {
      if (event_buffer_.empty()) {
        buffer_start_us_ = event->t;
      }
      event_buffer_.push_back(*event);
      if (event->t - buffer_start_us_ >= event_delta_us_) {
        publishEventsLocked();
      }
    }
  }

  void publishEventsLocked() {
    if (event_buffer_.empty()) {
      return;
    }
    dvs_msgs::EventArray message;
    message.header.seq = sequence_++;
    message.header.stamp = mappedTime(event_buffer_.back().t);
    message.header.frame_id = frame_id_;
    message.width = camera_->geometry().width();
    message.height = camera_->geometry().height();
    message.events.resize(event_buffer_.size());
    for (std::size_t index = 0; index < event_buffer_.size(); ++index) {
      const auto &source = event_buffer_[index];
      auto &target = message.events[index];
      target.x = source.x;
      target.y = source.y;
      target.polarity = source.p;
      target.ts = mappedTime(source.t);
    }
    waitUntil(message.header.stamp);
    events_pub_.publish(message);
    publishCameraInfo(message.header.stamp);
    event_buffer_.clear();
  }

  void flushEvents() {
    std::lock_guard<std::mutex> lock(event_mutex_);
    publishEventsLocked();
  }

  void triggerCallback(const Metavision::EventExtTrigger *begin,
                       const Metavision::EventExtTrigger *end) {
    if (begin >= end) {
      return;
    }
    event_camera_msgs::ExternalTriggerArray message;
    message.header.stamp = mappedTime((end - 1)->t);
    message.header.frame_id = frame_id_;
    message.events.resize(static_cast<std::size_t>(std::distance(begin, end)));
    for (std::size_t index = 0; index < message.events.size(); ++index) {
      message.events[index].ts = mappedTime(begin[index].t);
      message.events[index].channel = static_cast<std::uint16_t>(begin[index].id);
      message.events[index].polarity = begin[index].p != 0;
    }
    waitUntil(message.header.stamp);
    trigger_pub_.publish(message);
  }

  void publishCameraInfo(const ros::Time &stamp) {
    sensor_msgs::CameraInfo info = camera_info_manager_->getCameraInfo();
    info.width = camera_->geometry().width();
    info.height = camera_->geometry().height();
    info.header.stamp = stamp;
    info.header.frame_id = frame_id_;
    camera_info_pub_.publish(info);
  }

  ros::NodeHandle nh_;
  ros::NodeHandle pnh_;
  ros::Publisher events_pub_;
  ros::Publisher camera_info_pub_;
  ros::Publisher trigger_pub_;
  std::unique_ptr<camera_info_manager::CameraInfoManager> camera_info_manager_;
  std::unique_ptr<Metavision::Camera> camera_;
  std::string raw_file_;
  std::string frame_id_;
  std::string camera_name_;
  std::string camera_info_url_;
  std::string serial_;
  bool realtime_;
  double timestamp_offset_sec_;
  double timestamp_base_us_;
  double subscriber_wait_timeout_;
  std::int64_t event_delta_us_;
  Metavision::timestamp buffer_start_us_ = 0;
  std::uint32_t sequence_;
  std::vector<Metavision::EventCD> event_buffer_;
  std::mutex event_mutex_;
  std::atomic<bool> runtime_error_;
};

}  // namespace

int main(int argc, char **argv) {
  ros::init(argc, argv, "prophesee_raw_dvs_publisher");
  try {
    RawDvsPublisher publisher;
    return publisher.run();
  } catch (const std::exception &error) {
    ROS_FATAL_STREAM(error.what());
    return 1;
  }
}
