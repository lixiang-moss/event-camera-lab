#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <metavision/sdk/base/events/event_cd.h>
#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <metavision/sdk/driver/file_config_hints.h>
#include <prophesee_event_msgs/EventArray.h>
#include <ros/ros.h>
#include <sensor_msgs/CameraInfo.h>

namespace {

class RawPublisher {
 public:
  RawPublisher()
      : nh_(),
        pnh_("~"),
        event_delta_us_(1000),
        width_(0),
        height_(0),
        sequence_(0),
        published_events_(0),
        runtime_error_(false) {
    pnh_.param<std::string>("raw_file_to_read", raw_file_, "");
    pnh_.param<std::string>("camera_name", camera_name_, "camera");
    pnh_.param<std::string>("frame_id", frame_id_, "PropheseeCamera_optical_frame");
    double event_delta_t = 0.001;
    pnh_.param("event_delta_t", event_delta_t, event_delta_t);
    pnh_.param("subscriber_wait_timeout", subscriber_wait_timeout_, 5.0);
    event_delta_us_ = std::max<std::int64_t>(1, std::llround(event_delta_t * 1e6));

    if (raw_file_.empty()) {
      throw std::runtime_error("~raw_file_to_read is required");
    }

    const std::string topic_prefix = "/prophesee/" + camera_name_;
    events_pub_ = nh_.advertise<prophesee_event_msgs::EventArray>(
        topic_prefix + "/cd_events_buffer", 500);
    camera_info_pub_ = nh_.advertise<sensor_msgs::CameraInfo>(
        topic_prefix + "/camera_info", 10, true);

    auto hints = Metavision::FileConfigHints().real_time_playback(true);
    camera_ = Metavision::Camera::from_file(raw_file_, hints);
    const auto config = camera_.get_camera_configuration();
    width_ = camera_.geometry().width();
    height_ = camera_.geometry().height();
    serial_ = config.serial_number;

    camera_.cd().add_callback(
        [this](const Metavision::EventCD *begin, const Metavision::EventCD *end) {
          eventsCallback(begin, end);
        });
    camera_.add_runtime_error_callback([this](const Metavision::CameraException &error) {
      ROS_ERROR_STREAM("RAW playback error: " << error.what());
      runtime_error_.store(true);
    });
  }

  int run() {
    const ros::WallTime deadline =
        ros::WallTime::now() + ros::WallDuration(subscriber_wait_timeout_);
    while (ros::ok() && events_pub_.getNumSubscribers() == 0 &&
           ros::WallTime::now() < deadline) {
      ros::spinOnce();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    start_time_ = ros::Time::now();
    publishCameraInfo();
    if (!camera_.start()) {
      ROS_ERROR("Failed to start RAW playback");
      return 2;
    }

    ROS_INFO_STREAM("RAW playback started: " << raw_file_ << " serial=" << serial_
                                               << " event_delta_us=" << event_delta_us_);
    ros::WallRate loop_rate(100);
    while (ros::ok() && camera_.is_running() && !runtime_error_.load()) {
      ros::spinOnce();
      loop_rate.sleep();
    }
    camera_.stop();
    flush();
    publishCameraInfo();
    ros::WallDuration(0.5).sleep();
    ROS_INFO_STREAM("RAW playback completed; published_events=" << published_events_);
    return runtime_error_.load() ? 3 : 0;
  }

 private:
  void eventsCallback(const Metavision::EventCD *begin,
                      const Metavision::EventCD *end) {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    for (const auto *event = begin; event != end; ++event) {
      if (buffer_.empty()) {
        buffer_start_us_ = event->t;
      }
      buffer_.push_back(*event);
      if (event->t - buffer_start_us_ >= event_delta_us_) {
        publishBufferedEvents();
      }
    }
  }

  void flush() {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    publishBufferedEvents();
  }

  ros::Time mappedTime(Metavision::timestamp timestamp_us) const {
    ros::Time stamp;
    stamp.fromNSec(start_time_.toNSec() + static_cast<std::uint64_t>(timestamp_us) * 1000ULL);
    return stamp;
  }

  void publishBufferedEvents() {
    if (buffer_.empty()) {
      return;
    }

    prophesee_event_msgs::EventArray message;
    message.header.seq = sequence_++;
    message.header.stamp = mappedTime(buffer_.back().t);
    message.header.frame_id = frame_id_;
    message.width = width_;
    message.height = height_;
    message.events.resize(buffer_.size());
    for (std::size_t index = 0; index < buffer_.size(); ++index) {
      const auto &source = buffer_[index];
      auto &target = message.events[index];
      target.x = source.x;
      target.y = source.y;
      target.polarity = source.p;
      target.ts = mappedTime(source.t);
    }
    published_events_ += buffer_.size();
    events_pub_.publish(message);
    buffer_.clear();
  }

  void publishCameraInfo() {
    sensor_msgs::CameraInfo message;
    message.header.stamp = ros::Time::now();
    message.header.frame_id = frame_id_;
    message.width = width_;
    message.height = height_;
    camera_info_pub_.publish(message);
  }

  ros::NodeHandle nh_;
  ros::NodeHandle pnh_;
  ros::Publisher events_pub_;
  ros::Publisher camera_info_pub_;
  Metavision::Camera camera_;
  std::string raw_file_;
  std::string camera_name_;
  std::string frame_id_;
  std::string serial_;
  std::int64_t event_delta_us_;
  double subscriber_wait_timeout_;
  std::uint32_t width_;
  std::uint32_t height_;
  std::uint32_t sequence_;
  std::uint64_t published_events_;
  Metavision::timestamp buffer_start_us_ = 0;
  std::vector<Metavision::EventCD> buffer_;
  std::mutex buffer_mutex_;
  ros::Time start_time_;
  std::atomic<bool> runtime_error_;
};

}  // namespace

int main(int argc, char **argv) {
  ros::init(argc, argv, "prophesee_raw_publisher");
  try {
    RawPublisher publisher;
    return publisher.run();
  } catch (const std::exception &error) {
    ROS_FATAL_STREAM(error.what());
    return 1;
  }
}
