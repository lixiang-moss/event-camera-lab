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

class PropheseeDvsDriver {
 public:
  PropheseeDvsDriver()
      : nh_(),
        pnh_("~"),
        sequence_(0),
        event_delta_us_(1000),
        runtime_error_(false) {
    pnh_.param<std::string>("camera_serial", requested_serial_, "");
    pnh_.param<std::string>("camera_name", camera_name_, "");
    pnh_.param<std::string>("frame_id", frame_id_, "event_camera_optical_frame");
    pnh_.param<std::string>("camera_info_url", camera_info_url_, "");
    pnh_.param<std::string>("bias_file", bias_file_, "");
    pnh_.param<std::string>("sync_mode", sync_mode_, "standalone");
    pnh_.param("expected_width", expected_width_, 0);
    pnh_.param("expected_height", expected_height_, 0);
    pnh_.param("expected_generation_major", expected_generation_major_, 0);
    pnh_.param("expected_generation_minor", expected_generation_minor_, -1);
    pnh_.param<std::string>("expected_system_ids", expected_system_ids_, "");
    pnh_.param("trigger_enabled", trigger_enabled_, true);
    pnh_.param("trigger_channel", trigger_channel_, 0);
    double event_delta_t = 0.001;
    double timestamp_offset_sec = 0.0;
    pnh_.param("event_delta_t", event_delta_t, event_delta_t);
    pnh_.param("timestamp_offset_sec", timestamp_offset_sec, timestamp_offset_sec);
    event_delta_us_ = std::max<std::int64_t>(1, std::llround(event_delta_t * 1e6));
    timestamp_offset_ = timestamp_offset_sec > 0.0 ? ros::Time(timestamp_offset_sec)
                                                   : ros::Time::now();

    const auto source_identifier =
        event_camera_prophesee_tools::resolveOnlineSourceIdentifier(requested_serial_);
    camera_.reset(new Metavision::Camera(Metavision::Camera::from_serial(source_identifier)));
    serial_ = event_camera_prophesee_tools::cameraSerial(camera_.get());
    const auto config = camera_->get_camera_configuration();
    const auto width = static_cast<int>(camera_->geometry().width());
    const auto height = static_cast<int>(camera_->geometry().height());
    const auto generation_major = static_cast<int>(camera_->generation().version_major());
    const auto generation_minor = static_cast<int>(camera_->generation().version_minor());
    event_camera_prophesee_tools::validateSystemId(
        camera_.get(), expected_system_ids_, "Connected camera");
    if ((expected_width_ > 0 && width != expected_width_) ||
        (expected_height_ > 0 && height != expected_height_) ||
        (expected_generation_major_ > 0 && generation_major != expected_generation_major_) ||
        (expected_generation_minor_ >= 0 && generation_minor != expected_generation_minor_)) {
      throw std::runtime_error("Connected camera does not match the profile: serial=" + serial_ +
                               " geometry=" + std::to_string(width) + "x" +
                               std::to_string(height) + " generation=" +
                               std::to_string(generation_major) + "." +
                               std::to_string(generation_minor));
    }

    if (camera_name_.empty()) {
      camera_name_ = "prophesee_" + serial_;
    }
    if (camera_info_url_.empty()) {
      camera_info_url_ = "file:///root/.ros/camera_info/prophesee_" + serial_ + ".yaml";
    }
    camera_info_manager_.reset(
        new camera_info_manager::CameraInfoManager(nh_, camera_name_, camera_info_url_));

    if (!bias_file_.empty()) {
      camera_->biases().set_from_file(bias_file_);
    }
    event_camera_prophesee_tools::configureSynchronization(camera_.get(), sync_mode_);
    if (trigger_enabled_) {
      event_camera_prophesee_tools::enableTriggerInput(camera_.get(), trigger_channel_);
    }

    events_pub_ = nh_.advertise<dvs_msgs::EventArray>("events", 1000);
    camera_info_pub_ = nh_.advertise<sensor_msgs::CameraInfo>("camera_info", 10, true);
    trigger_pub_ = nh_.advertise<event_camera_msgs::ExternalTriggerArray>("ext_trigger", 100);

    camera_->cd().add_callback(
        [this](const Metavision::EventCD *begin, const Metavision::EventCD *end) {
          eventsCallback(begin, end);
        });
    if (trigger_enabled_) {
      camera_->ext_trigger().add_callback(
          [this](const Metavision::EventExtTrigger *begin,
                 const Metavision::EventExtTrigger *end) {
            triggerCallback(begin, end);
          });
    }
    camera_->add_runtime_error_callback([this](const Metavision::CameraException &error) {
      ROS_ERROR_STREAM("Prophesee runtime error: " << error.what());
      runtime_error_.store(true);
    });

    pnh_.setParam("selected_serial", serial_);
    pnh_.setParam("width", width);
    pnh_.setParam("height", height);
    pnh_.setParam("generation", std::to_string(generation_major) + "." +
                                     std::to_string(generation_minor));
    pnh_.setParam(
        "system_id",
        static_cast<int>(event_camera_prophesee_tools::cameraSystemId(camera_.get())));
    pnh_.setParam("event_delta_t", static_cast<double>(event_delta_us_) / 1e6);
    pnh_.setParam("sync_mode", sync_mode_);
    pnh_.setParam("openeb_plugin", event_camera_prophesee_tools::pluginName(config));
    publishCameraInfo(ros::Time::now());
  }

  int run() {
    if (!camera_->start()) {
      ROS_ERROR("Failed to start Prophesee camera");
      return 2;
    }
    ROS_INFO_STREAM("Prophesee dvs_msgs driver started: serial=" << serial_
                    << " namespace=" << nh_.getNamespace()
                    << " sync_mode=" << sync_mode_
                    << " event_delta_us=" << event_delta_us_);
    ros::WallRate rate(1000);
    while (ros::ok() && camera_->is_running() && !runtime_error_.load()) {
      ros::spinOnce();
      flushEvents();
      rate.sleep();
    }
    camera_->stop();
    flushEvents();
    return runtime_error_.load() ? 3 : 0;
  }

 private:
  ros::Time mappedTime(Metavision::timestamp timestamp_us) const {
    return timestamp_offset_ + ros::Duration(static_cast<double>(timestamp_us) / 1e6);
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
    trigger_pub_.publish(message);
  }

  void publishCameraInfo(const ros::Time &stamp) {
    if (!camera_info_manager_) {
      return;
    }
    sensor_msgs::CameraInfo info = camera_info_manager_->getCameraInfo();
    const auto width = camera_->geometry().width();
    const auto height = camera_->geometry().height();
    if (info.width != 0 && info.height != 0 &&
        (info.width != width || info.height != height)) {
      ROS_ERROR_THROTTLE(5.0, "Ignoring calibration with resolution %ux%u for %ux%u stream",
                         info.width, info.height, width, height);
      info = sensor_msgs::CameraInfo();
    }
    info.width = width;
    info.height = height;
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
  std::string requested_serial_;
  std::string serial_;
  std::string camera_name_;
  std::string frame_id_;
  std::string camera_info_url_;
  std::string bias_file_;
  std::string expected_system_ids_;
  std::string sync_mode_;
  int expected_width_;
  int expected_height_;
  int expected_generation_major_;
  int expected_generation_minor_;
  bool trigger_enabled_;
  int trigger_channel_;
  std::uint32_t sequence_;
  std::int64_t event_delta_us_;
  Metavision::timestamp buffer_start_us_ = 0;
  ros::Time timestamp_offset_;
  std::vector<Metavision::EventCD> event_buffer_;
  std::mutex event_mutex_;
  std::atomic<bool> runtime_error_;
};

}  // namespace

int main(int argc, char **argv) {
  ros::init(argc, argv, "event_camera_driver");
  try {
    PropheseeDvsDriver driver;
    return driver.run();
  } catch (const std::exception &error) {
    ROS_FATAL_STREAM(error.what());
    return 1;
  }
}
