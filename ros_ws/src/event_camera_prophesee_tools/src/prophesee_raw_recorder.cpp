#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <metavision/hal/facilities/i_hw_identification.h>

#include "event_camera_prophesee_tools/openeb_compat.h"

namespace {

std::atomic<bool> stop_requested(false);
std::atomic<bool> runtime_error(false);

void handleSignal(int) {
  stop_requested.store(true);
}

struct Options {
  std::string output;
  std::string serial;
  std::string sync_mode = "standalone";
  std::string bias_file;
  double duration_seconds = 0.0;
};

Options parseOptions(int argc, char **argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument(argv[index]);
    if (argument == "--output" && index + 1 < argc) {
      options.output = argv[++index];
    } else if (argument == "--serial" && index + 1 < argc) {
      options.serial = argv[++index];
    } else if (argument == "--sync-mode" && index + 1 < argc) {
      options.sync_mode = argv[++index];
    } else if (argument == "--bias-file" && index + 1 < argc) {
      options.bias_file = argv[++index];
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
    const auto source_identifier =
        event_camera_prophesee_tools::resolveOnlineSourceIdentifier(options.serial);
    auto camera = Metavision::Camera::from_serial(source_identifier);
    const auto config = camera.get_camera_configuration();
    const auto serial = event_camera_prophesee_tools::cameraSerial(&camera);

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);
    camera.add_runtime_error_callback([](const Metavision::CameraException &error) {
      std::cerr << "Camera runtime error: " << error.what() << std::endl;
      runtime_error.store(true);
      stop_requested.store(true);
    });

    if (!options.bias_file.empty()) {
      camera.biases().set_from_file(options.bias_file);
    }
    event_camera_prophesee_tools::configureSynchronization(&camera, options.sync_mode);
    event_camera_prophesee_tools::enableTriggerInput(&camera, 0);
    event_camera_prophesee_tools::startRecording(&camera, options.output);
    if (!camera.start()) {
      event_camera_prophesee_tools::stopRecording(&camera, options.output);
      throw std::runtime_error("Failed to start camera");
    }

    std::cout << "Recording Prophesee RAW\n"
              << "serial=" << serial << "\n"
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

    const bool stopped = camera.stop();
    if (!stopped && !runtime_error.load()) {
      throw std::runtime_error("Failed to stop camera and finalize RAW recording");
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
