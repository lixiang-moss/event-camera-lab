#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
#include <thread>

#include <metavision/sdk/base/events/event_cd.h>
#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <metavision/sdk/driver/file_config_hints.h>

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "Usage: prophesee_raw_info FILE.raw" << std::endl;
    return 1;
  }

  try {
    auto hints = Metavision::FileConfigHints().real_time_playback(false);
    auto camera = Metavision::Camera::from_file(argv[1], hints);
    const auto config = camera.get_camera_configuration();
    const auto width = camera.geometry().width();
    const auto height = camera.geometry().height();

    std::atomic<std::uint64_t> count(0);
    std::atomic<Metavision::timestamp> first(std::numeric_limits<Metavision::timestamp>::max());
    std::atomic<Metavision::timestamp> last(-1);
    std::atomic<bool> runtime_error(false);
    camera.add_runtime_error_callback([&](const Metavision::CameraException &error) {
      std::cerr << "RAW decode error: " << error.what() << std::endl;
      runtime_error.store(true);
    });
    camera.cd().add_callback([&](const Metavision::EventCD *begin, const Metavision::EventCD *end) {
      if (begin >= end) {
        return;
      }
      count.fetch_add(static_cast<std::uint64_t>(std::distance(begin, end)));
      auto current_first = first.load();
      while (begin->t < current_first && !first.compare_exchange_weak(current_first, begin->t)) {
      }
      auto current_last = last.load();
      const auto batch_last = (end - 1)->t;
      while (batch_last > current_last && !last.compare_exchange_weak(current_last, batch_last)) {
      }
    });

    if (!camera.start()) {
      std::cerr << "Failed to start RAW decoding" << std::endl;
      return 3;
    }
    while (camera.is_running()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    camera.stop();
    if (runtime_error.load()) {
      return 3;
    }

    const auto first_timestamp = first.load() == std::numeric_limits<Metavision::timestamp>::max()
                                     ? 0
                                     : first.load();
    const auto last_timestamp = std::max<Metavision::timestamp>(0, last.load());
    const auto duration = last_timestamp >= first_timestamp ? last_timestamp - first_timestamp : 0;

    std::cout << "path=" << argv[1] << "\n"
              << "serial=" << config.serial_number << "\n"
              << "width=" << width << "\n"
              << "height=" << height << "\n"
              << "plugin=" << config.plugin_name << "\n"
              << "encoding=" << config.data_encoding_format << "\n"
              << "firmware=" << config.firmware_version << "\n"
              << "cd_event_count=" << count.load() << "\n"
              << "first_timestamp_us=" << first_timestamp << "\n"
              << "last_timestamp_us=" << last_timestamp << "\n"
              << "duration_us=" << duration << std::endl;
  } catch (const Metavision::CameraException &error) {
    std::cerr << error.what() << std::endl;
    return 2;
  }
  return 0;
}
