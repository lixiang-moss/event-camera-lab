#pragma once

#include <stdexcept>
#include <set>
#include <sstream>
#include <string>

#include <metavision/sdk/driver/camera.h>
#include <metavision/hal/facilities/i_hw_identification.h>
#include <metavision/hal/facilities/i_trigger_in.h>

#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
#include <metavision/hal/facilities/i_device_control.h>
#include <metavision/hal/utils/raw_file_config.h>
#else
#include <metavision/hal/facilities/i_camera_synchronization.h>
#include <metavision/sdk/driver/file_config_hints.h>
#endif

namespace event_camera_prophesee_tools {

inline std::string canonicalSerial(const std::string &identifier) {
  const auto separator = identifier.find_last_of(':');
  return separator == std::string::npos ? identifier
                                        : identifier.substr(separator + 1);
}

inline std::string resolveOnlineSourceIdentifier(const std::string &requested) {
  if (requested.find(':') != std::string::npos) {
    return requested;
  }
  std::set<std::string> sources;
  for (const auto &source_type : Metavision::Camera::list_online_sources()) {
    sources.insert(source_type.second.begin(), source_type.second.end());
  }
  if (requested.empty()) {
    if (sources.size() != 1) {
      throw std::runtime_error(
          "Expected exactly one Prophesee camera when serial is empty; found " +
          std::to_string(sources.size()));
    }
    return *sources.begin();
  }
  std::string match;
  for (const auto &source : sources) {
    if (source == requested || canonicalSerial(source) == requested) {
      if (!match.empty() && match != source) {
        throw std::runtime_error("Camera serial is ambiguous: " + requested);
      }
      match = source;
    }
  }
  if (match.empty()) {
    throw std::runtime_error("Prophesee camera serial not found: " + requested);
  }
  return match;
}

inline std::string cameraSerial(Metavision::Camera *camera) {
  auto *identification =
      camera->get_device().get_facility<Metavision::I_HW_Identification>();
  if (identification != nullptr && !identification->get_serial().empty()) {
    return canonicalSerial(identification->get_serial());
  }
  return canonicalSerial(camera->get_camera_configuration().serial_number);
}

inline long cameraSystemId(Metavision::Camera *camera) {
  auto *identification =
      camera->get_device().get_facility<Metavision::I_HW_Identification>();
  if (identification == nullptr) {
    throw std::runtime_error("Camera hardware identification is unavailable");
  }
  return identification->get_system_id();
}

inline void validateSystemId(Metavision::Camera *camera,
                             const std::string &expected_ids,
                             const std::string &label) {
  if (expected_ids.empty()) {
    return;
  }
  const long actual = cameraSystemId(camera);
  std::istringstream stream(expected_ids);
  std::string token;
  while (std::getline(stream, token, ',')) {
    if (!token.empty() && std::stol(token, nullptr, 0) == actual) {
      return;
    }
  }
  throw std::runtime_error(label + " system_ID=" + std::to_string(actual) +
                           " is not allowed by profile (expected " +
                           expected_ids + ")");
}

inline std::string pluginName(const Metavision::CameraConfiguration &config) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  (void)config;
  return "openeb-3.1-camera-plugin";
#else
  return config.plugin_name;
#endif
}

inline std::string encodingName(const Metavision::CameraConfiguration &config) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  (void)config;
  return "from-raw-header";
#else
  return config.data_encoding_format;
#endif
}

inline std::string firmwareVersion(const Metavision::CameraConfiguration &config) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  (void)config;
  return "";
#else
  return config.firmware_version;
#endif
}

inline Metavision::Camera openRawFile(const std::string &path, bool realtime,
                                      bool time_shift) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  Metavision::RawFileConfig config;
  config.do_time_shifting_ = time_shift;
  return Metavision::Camera::from_file(path, realtime, config);
#else
  auto hints = Metavision::FileConfigHints()
                   .real_time_playback(realtime)
                   .time_shift(time_shift);
  return Metavision::Camera::from_file(path, hints);
#endif
}

inline void startRecording(Metavision::Camera *camera,
                           const std::string &path) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  camera->start_recording(path);
#else
  if (!camera->start_recording(path)) {
    throw std::runtime_error("Failed to start RAW recording: " + path);
  }
#endif
}

inline void stopRecording(Metavision::Camera *camera,
                          const std::string &path) {
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  camera->stop_recording();
#else
  if (!camera->stop_recording(path)) {
    throw std::runtime_error("Failed to close RAW recording cleanly: " + path);
  }
#endif
}

inline void configureSynchronization(Metavision::Camera *camera,
                                     const std::string &mode) {
  bool configured = false;
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  auto *facility =
      camera->get_device().get_facility<Metavision::I_DeviceControl>();
#else
  auto *facility = camera->get_device().get_facility<
      Metavision::I_CameraSynchronization>();
#endif
  if (facility == nullptr) {
    throw std::runtime_error("Camera synchronization facility is unavailable");
  }
  if (mode == "standalone") {
    configured = facility->set_mode_standalone();
  } else if (mode == "master") {
    configured = facility->set_mode_master();
  } else if (mode == "slave") {
    configured = facility->set_mode_slave();
  } else {
    throw std::runtime_error("Unknown synchronization mode: " + mode);
  }
  if (!configured) {
    throw std::runtime_error("Failed to configure synchronization mode: " + mode);
  }
}

inline void enableTriggerInput(Metavision::Camera *camera,
                               std::uint32_t channel) {
  auto *facility = camera->get_device().get_facility<Metavision::I_TriggerIn>();
  if (facility == nullptr) {
    throw std::runtime_error("External trigger facility is unavailable");
  }
#if EVENT_CAMERA_OPENEB_API_LEVEL == 3
  const bool enabled = facility->enable(channel);
#else
  if (channel > static_cast<std::uint32_t>(Metavision::I_TriggerIn::Channel::Loopback)) {
    throw std::runtime_error("Unsupported external trigger channel " +
                             std::to_string(channel));
  }
  const bool enabled = facility->enable(
      static_cast<Metavision::I_TriggerIn::Channel>(channel));
#endif
  if (!enabled) {
    throw std::runtime_error("Failed to enable external trigger channel " +
                             std::to_string(channel));
  }
}

}  // namespace event_camera_prophesee_tools
