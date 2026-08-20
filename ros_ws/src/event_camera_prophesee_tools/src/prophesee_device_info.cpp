#include <iostream>
#include <set>
#include <string>
#include <vector>

#include <metavision/sdk/driver/camera.h>
#include <metavision/sdk/driver/camera_exception.h>
#include <metavision/hal/facilities/i_hw_identification.h>

#include "event_camera_prophesee_tools/openeb_compat.h"

namespace {

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
  const bool serial_only = argc == 2 && std::string(argv[1]) == "--single-serial";
  const bool list_serials = argc == 2 && std::string(argv[1]) == "--list-serials";
  const bool resolve_source = argc == 3 && std::string(argv[1]) == "--resolve-source";
  std::set<std::string> unique_sources;
  const auto sources = Metavision::Camera::list_online_sources();
  for (const auto &source_type : sources) {
    unique_sources.insert(source_type.second.begin(), source_type.second.end());
  }

  if (list_serials) {
    for (const auto &source : unique_sources) {
      std::cout << event_camera_prophesee_tools::canonicalSerial(source) << std::endl;
    }
    return 0;
  }
  if (resolve_source) {
    const std::string requested(argv[2]);
    for (const auto &source : unique_sources) {
      if (source == requested ||
          event_camera_prophesee_tools::canonicalSerial(source) == requested) {
        std::cout << source << std::endl;
        return 0;
      }
    }
    std::cerr << "Prophesee camera serial not found: " << requested << std::endl;
    return 5;
  }

  if (unique_sources.size() != 1) {
    std::cerr << "Expected exactly one Prophesee camera, found " << unique_sources.size() << std::endl;
    for (const auto &source : unique_sources) {
      std::cerr << "  " << source << std::endl;
    }
    return unique_sources.empty() ? 2 : 3;
  }

  try {
    auto camera = Metavision::Camera::from_serial(*unique_sources.begin());
    const auto &config = camera.get_camera_configuration();
    const auto serial = event_camera_prophesee_tools::cameraSerial(&camera);
    if (serial_only) {
      std::cout << serial << std::endl;
      return 0;
    }

    const auto &geometry = camera.geometry();
    const auto &generation = camera.generation();
    std::cout << "camera_count=1\n"
              << "serial=" << serial << "\n"
              << "width=" << geometry.width() << "\n"
              << "height=" << geometry.height() << "\n"
              << "generation_major=" << generation.version_major() << "\n"
              << "generation_minor=" << generation.version_minor() << "\n"
              << "system_id=" << event_camera_prophesee_tools::cameraSystemId(&camera) << "\n"
              << "plugin=" << event_camera_prophesee_tools::pluginName(config) << "\n"
              << "encoding=" << event_camera_prophesee_tools::encodingName(config) << "\n"
              << "firmware=" << firmwareVersion(&camera) << std::endl;
  } catch (const Metavision::CameraException &error) {
    std::cerr << error.what() << std::endl;
    return 4;
  }
  return 0;
}
