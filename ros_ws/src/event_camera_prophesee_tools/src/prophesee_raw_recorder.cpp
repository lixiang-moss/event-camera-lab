#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <metavision/hal/facilities/i_hw_identification.h>

namespace {

std::atomic<bool> stop_requested(false);
std::atomic<bool> runtime_error(false);

void handleSignal(int) {
  stop_requested.store(true);
}

struct Options {
  std::string output;
  double duration_seconds = 0.0;
};

Options parseOptions(int argc, char **argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument(argv[index]);
    if (argument == "--output" && index + 1 < argc) {
      options.output = argv[++index];
    } else if (argument == "--duration" && index + 1 < argc) {
      options.duration_seconds = std::stod(argv[++index]);
    } else {
      throw std::invalid_argument("Unknown or incomplete argument: " + argument);
    }
  }
  if (options.output.empty()) {
    throw std::invalid_argument("--output is required");
  }
  if (options.duration_seconds < 0.0) {
    throw std::invalid_argument("--duration must be zero or positive");
  }
  return options;
}

std::string requireSingleSerial() {
  std::set<std::string> serials;
  for (const auto &source_type : Metavision::Camera::list_online_sources()) {
    serials.insert(source_type.second.begin(), source_type.second.end());
  }
  if (serials.size() != 1) {
    throw std::runtime_error("Expected exactly one Prophesee camera, found " +
                             std::to_string(serials.size()));
  }
  return *serials.begin();
}

std::string firmwareVersion(Metavision::Camera *camera) {
  auto *identification =
      camera->get_device().get_facility<Metavision::I_HW_Identification>();
  if (identification == nullptr) {
    return "";
  }
  const auto system_info = identification->get_system_info();
  for (const auto &key : {"EVK4 Release Version", "System Version"}) {
    const auto found = system_info.find(key);
    if (found != system_info.end() && !found->second.empty()) {
      return found->second;
    }
  }
  return "";
}

}  // namespace

int main(int argc, char **argv) {
  try {
    const auto options = parseOptions(argc, argv);
    const auto serial = requireSingleSerial();
    auto camera = Metavision::Camera::from_serial(serial);
    const auto config = camera.get_camera_configuration();

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);
    camera.add_runtime_error_callback([](const Metavision::CameraException &error) {
      std::cerr << "Camera runtime error: " << error.what() << std::endl;
      runtime_error.store(true);
      stop_requested.store(true);
    });

    if (!camera.start_recording(options.output)) {
      throw std::runtime_error("Failed to start RAW recording: " + options.output);
    }
    if (!camera.start()) {
      throw std::runtime_error("Failed to start camera");
    }

    std::cout << "Recording EVK4 RAW\n"
              << "serial=" << config.serial_number << "\n"
              << "firmware=" << firmwareVersion(&camera) << "\n"
              << "output=" << options.output << std::endl;

    const auto start = std::chrono::steady_clock::now();
    while (!stop_requested.load() && camera.is_running()) {
      if (options.duration_seconds > 0.0) {
        const std::chrono::duration<double> elapsed = std::chrono::steady_clock::now() - start;
        if (elapsed.count() >= options.duration_seconds) {
          break;
        }
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const bool recording_stopped = camera.stop_recording(options.output);
    camera.stop();
    if (!recording_stopped) {
      throw std::runtime_error("Failed to close RAW recording cleanly: " + options.output);
    }
    if (runtime_error.load()) {
      std::cerr << "RAW recording stopped because of a camera runtime error" << std::endl;
      return 2;
    }
    std::cout << "RAW recording closed cleanly" << std::endl;
  } catch (const std::exception &error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
  return 0;
}
