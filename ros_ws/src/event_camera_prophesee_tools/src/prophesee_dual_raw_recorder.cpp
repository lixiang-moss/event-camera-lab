#include <atomic>
#include <chrono>
#include <csignal>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>

#include "event_camera_prophesee_tools/openeb_compat.h"

namespace {

std::atomic<bool> stop_requested(false);
std::atomic<bool> runtime_error(false);

void handleSignal(int) {
  stop_requested.store(true);
}

struct Options {
  std::string cam0_serial;
  std::string cam1_serial;
  std::string cam0_output;
  std::string cam1_output;
  std::string cam0_bias_file;
  std::string cam1_bias_file;
  std::string sync_mode = "standalone";
  int expected_width = 0;
  int expected_height = 0;
  int expected_generation_major = 0;
  std::string expected_system_ids;
  double duration_seconds = 0.0;
};

Options parseOptions(int argc, char **argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument(argv[index]);
    auto require_value = [&](std::string *value) {
      if (index + 1 >= argc) {
        throw std::invalid_argument("Missing value for " + argument);
      }
      *value = argv[++index];
    };
    if (argument == "--cam0-serial") {
      require_value(&options.cam0_serial);
    } else if (argument == "--cam1-serial") {
      require_value(&options.cam1_serial);
    } else if (argument == "--cam0-output") {
      require_value(&options.cam0_output);
    } else if (argument == "--cam1-output") {
      require_value(&options.cam1_output);
    } else if (argument == "--cam0-bias-file") {
      require_value(&options.cam0_bias_file);
    } else if (argument == "--cam1-bias-file") {
      require_value(&options.cam1_bias_file);
    } else if (argument == "--sync-mode") {
      require_value(&options.sync_mode);
    } else if (argument == "--duration" && index + 1 < argc) {
      options.duration_seconds = std::stod(argv[++index]);
    } else if (argument == "--expected-width" && index + 1 < argc) {
      options.expected_width = std::stoi(argv[++index]);
    } else if (argument == "--expected-height" && index + 1 < argc) {
      options.expected_height = std::stoi(argv[++index]);
    } else if (argument == "--expected-generation-major" && index + 1 < argc) {
      options.expected_generation_major = std::stoi(argv[++index]);
    } else if (argument == "--expected-system-ids") {
      require_value(&options.expected_system_ids);
    } else {
      throw std::invalid_argument("Unknown or incomplete argument: " + argument);
    }
  }
  if (options.cam0_serial.empty() || options.cam1_serial.empty() ||
      options.cam0_output.empty() || options.cam1_output.empty()) {
    throw std::invalid_argument("Both serials and both output paths are required");
  }
  if (options.cam0_serial == options.cam1_serial) {
    throw std::invalid_argument("cam0 and cam1 serials must differ");
  }
  if (options.sync_mode != "standalone" && options.sync_mode != "master_slave") {
    throw std::invalid_argument("--sync-mode must be standalone or master_slave");
  }
  if (options.duration_seconds < 0.0) {
    throw std::invalid_argument("--duration must be zero or positive");
  }
  return options;
}

void validateGeometry(Metavision::Camera *camera, const Options &options,
                      const std::string &label) {
  event_camera_prophesee_tools::validateSystemId(
      camera, options.expected_system_ids, label);
  const int width = static_cast<int>(camera->geometry().width());
  const int height = static_cast<int>(camera->geometry().height());
  const int generation_major =
      static_cast<int>(camera->generation().version_major());
  if ((options.expected_width > 0 && width != options.expected_width) ||
      (options.expected_height > 0 && height != options.expected_height) ||
      (options.expected_generation_major > 0 &&
       generation_major != options.expected_generation_major)) {
    throw std::runtime_error(label + " geometry " + std::to_string(width) + "x" +
                             std::to_string(height) + " generation " +
                             std::to_string(generation_major) +
                             " does not match the profile");
  }
}

}  // namespace

int main(int argc, char **argv) {
  try {
    const auto options = parseOptions(argc, argv);
    const auto cam0_source =
        event_camera_prophesee_tools::resolveOnlineSourceIdentifier(options.cam0_serial);
    const auto cam1_source =
        event_camera_prophesee_tools::resolveOnlineSourceIdentifier(options.cam1_serial);
    auto cam0 = Metavision::Camera::from_serial(cam0_source);
    auto cam1 = Metavision::Camera::from_serial(cam1_source);
    validateGeometry(&cam0, options, "cam0");
    validateGeometry(&cam1, options, "cam1");
    if (!options.cam0_bias_file.empty()) {
      cam0.biases().set_from_file(options.cam0_bias_file);
    }
    if (!options.cam1_bias_file.empty()) {
      cam1.biases().set_from_file(options.cam1_bias_file);
    }

    if (options.sync_mode == "master_slave") {
      event_camera_prophesee_tools::configureSynchronization(&cam1, "slave");
      event_camera_prophesee_tools::configureSynchronization(&cam0, "master");
    } else {
      event_camera_prophesee_tools::configureSynchronization(&cam0, "standalone");
      event_camera_prophesee_tools::configureSynchronization(&cam1, "standalone");
    }
    event_camera_prophesee_tools::enableTriggerInput(&cam0, 0);
    event_camera_prophesee_tools::enableTriggerInput(&cam1, 0);

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);
    auto error_callback = [](const Metavision::CameraException &error) {
      std::cerr << "Camera runtime error: " << error.what() << std::endl;
      runtime_error.store(true);
      stop_requested.store(true);
    };
    cam0.add_runtime_error_callback(error_callback);
    cam1.add_runtime_error_callback(error_callback);

    event_camera_prophesee_tools::startRecording(&cam0, options.cam0_output);
    event_camera_prophesee_tools::startRecording(&cam1, options.cam1_output);
    if (!cam1.start()) {
      event_camera_prophesee_tools::stopRecording(&cam0, options.cam0_output);
      event_camera_prophesee_tools::stopRecording(&cam1, options.cam1_output);
      throw std::runtime_error("Failed to start cam1");
    }
    if (options.sync_mode == "master_slave") {
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
    if (!cam0.start()) {
      cam1.stop();
      event_camera_prophesee_tools::stopRecording(&cam0, options.cam0_output);
      throw std::runtime_error("Failed to start cam0");
    }

    std::cout << "Recording paired Prophesee RAW\n"
              << "cam0_serial=" << event_camera_prophesee_tools::cameraSerial(&cam0) << "\n"
              << "cam1_serial=" << event_camera_prophesee_tools::cameraSerial(&cam1) << "\n"
              << "sync_mode=" << options.sync_mode << "\n"
              << "cam0_output=" << options.cam0_output << "\n"
              << "cam1_output=" << options.cam1_output << std::endl;

    const auto start = std::chrono::steady_clock::now();
    while (!stop_requested.load() && cam0.is_running() && cam1.is_running()) {
      if (options.duration_seconds > 0.0) {
        const std::chrono::duration<double> elapsed = std::chrono::steady_clock::now() - start;
        if (elapsed.count() >= options.duration_seconds) {
          break;
        }
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const bool cam0_stopped = cam0.stop();
    const bool cam1_stopped = cam1.stop();
    if ((!cam0_stopped || !cam1_stopped) && !runtime_error.load()) {
      throw std::runtime_error("Failed to stop both cameras and finalize paired RAW recordings");
    }
    if (runtime_error.load()) {
      return 2;
    }
    std::cout << "Paired RAW recording closed cleanly" << std::endl;
  } catch (const std::exception &error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
  return 0;
}
