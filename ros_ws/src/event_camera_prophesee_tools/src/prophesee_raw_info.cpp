#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
#include <thread>

#include <metavision/sdk/base/events/event_cd.h>
#include <metavision/sdk/base/events/event_ext_trigger.h>
#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>

#include "event_camera_prophesee_tools/openeb_compat.h"

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "Usage: prophesee_raw_info FILE.raw" << std::endl;
    return 1;
  }

  try {
    auto camera = event_camera_prophesee_tools::openRawFile(argv[1], false, false);
    const auto config = camera.get_camera_configuration();
    const auto width = camera.geometry().width();
    const auto height = camera.geometry().height();
    const auto generation_major = camera.generation().version_major();
    const auto generation_minor = camera.generation().version_minor();

    std::atomic<std::uint64_t> count(0);
    std::atomic<Metavision::timestamp> cd_first(
        std::numeric_limits<Metavision::timestamp>::max());
    std::atomic<Metavision::timestamp> cd_last(-1);
    std::atomic<Metavision::timestamp> trigger_first(
        std::numeric_limits<Metavision::timestamp>::max());
    std::atomic<Metavision::timestamp> trigger_last(-1);
    std::atomic<bool> runtime_error(false);
    std::atomic<std::uint64_t> trigger_count(0);
    camera.add_runtime_error_callback([&](const Metavision::CameraException &error) {
      std::cerr << "RAW decode error: " << error.what() << std::endl;
      runtime_error.store(true);
    });
    camera.cd().add_callback([&](const Metavision::EventCD *begin, const Metavision::EventCD *end) {
      if (begin >= end) {
        return;
      }
      count.fetch_add(static_cast<std::uint64_t>(std::distance(begin, end)));
      auto current_first = cd_first.load();
      while (begin->t < current_first &&
             !cd_first.compare_exchange_weak(current_first, begin->t)) {
      }
      auto current_last = cd_last.load();
      const auto batch_last = (end - 1)->t;
      while (batch_last > current_last &&
             !cd_last.compare_exchange_weak(current_last, batch_last)) {
      }
    });
    camera.ext_trigger().add_callback(
        [&](const Metavision::EventExtTrigger *begin,
            const Metavision::EventExtTrigger *end) {
          trigger_count.fetch_add(
              static_cast<std::uint64_t>(std::distance(begin, end)));
          if (begin >= end) {
            return;
          }
          auto current_first = trigger_first.load();
          while (begin->t < current_first &&
                 !trigger_first.compare_exchange_weak(current_first, begin->t)) {
          }
          auto current_last = trigger_last.load();
          const auto batch_last = (end - 1)->t;
          while (batch_last > current_last &&
                 !trigger_last.compare_exchange_weak(current_last, batch_last)) {
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

    const auto no_timestamp = std::numeric_limits<Metavision::timestamp>::max();
    const auto cd_first_timestamp = cd_first.load() == no_timestamp ? 0 : cd_first.load();
    const auto cd_last_timestamp = std::max<Metavision::timestamp>(0, cd_last.load());
    const auto trigger_first_timestamp =
        trigger_first.load() == no_timestamp ? 0 : trigger_first.load();
    const auto trigger_last_timestamp =
        std::max<Metavision::timestamp>(0, trigger_last.load());
    const bool has_cd = count.load() > 0;
    const bool has_trigger = trigger_count.load() > 0;
    const auto first_timestamp =
        has_cd && has_trigger
            ? std::min(cd_first_timestamp, trigger_first_timestamp)
            : (has_cd ? cd_first_timestamp : trigger_first_timestamp);
    const auto last_timestamp = std::max(cd_last_timestamp, trigger_last_timestamp);
    const auto duration = last_timestamp >= first_timestamp ? last_timestamp - first_timestamp : 0;

    std::cout << "path=" << argv[1] << "\n"
              << "serial=" << event_camera_prophesee_tools::cameraSerial(&camera) << "\n"
              << "width=" << width << "\n"
              << "height=" << height << "\n"
              << "generation_major=" << generation_major << "\n"
              << "generation_minor=" << generation_minor << "\n"
              << "system_id=" << event_camera_prophesee_tools::cameraSystemId(&camera) << "\n"
              << "plugin=" << event_camera_prophesee_tools::pluginName(config) << "\n"
              << "encoding=" << event_camera_prophesee_tools::encodingName(config) << "\n"
              << "firmware=" << event_camera_prophesee_tools::firmwareVersion(config) << "\n"
              << "cd_event_count=" << count.load() << "\n"
              << "trigger_event_count=" << trigger_count.load() << "\n"
              << "first_cd_timestamp_us=" << cd_first_timestamp << "\n"
              << "last_cd_timestamp_us=" << cd_last_timestamp << "\n"
              << "first_trigger_timestamp_us=" << trigger_first_timestamp << "\n"
              << "last_trigger_timestamp_us=" << trigger_last_timestamp << "\n"
              << "first_timestamp_us=" << first_timestamp << "\n"
              << "last_timestamp_us=" << last_timestamp << "\n"
              << "duration_us=" << duration << std::endl;
  } catch (const Metavision::CameraException &error) {
    std::cerr << error.what() << std::endl;
    return 2;
  }
  return 0;
}
