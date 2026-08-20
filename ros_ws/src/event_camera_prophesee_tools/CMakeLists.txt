cmake_minimum_required(VERSION 3.0.2)
project(event_camera_prophesee_tools)

add_compile_options(-std=c++14 -O3)

find_package(catkin REQUIRED COMPONENTS
  camera_info_manager
  dvs_msgs
  event_camera_msgs
  prophesee_event_msgs
  roscpp
  sensor_msgs
)
find_package(MetavisionSDK COMPONENTS driver REQUIRED)

if("$ENV{OPENEB_API_LEVEL}" STREQUAL "3")
  add_compile_definitions(EVENT_CAMERA_OPENEB_API_LEVEL=3)
else()
  add_compile_definitions(EVENT_CAMERA_OPENEB_API_LEVEL=4)
endif()

catkin_package(
  INCLUDE_DIRS include
  CATKIN_DEPENDS camera_info_manager dvs_msgs event_camera_msgs prophesee_event_msgs roscpp sensor_msgs
)

include_directories(include ${catkin_INCLUDE_DIRS})

add_executable(camera_info_gate src/camera_info_gate.cpp)
target_link_libraries(camera_info_gate ${catkin_LIBRARIES})
add_dependencies(camera_info_gate ${catkin_EXPORTED_TARGETS})

add_executable(prophesee_event_adapter src/prophesee_event_adapter.cpp)
target_link_libraries(prophesee_event_adapter ${catkin_LIBRARIES})
add_dependencies(prophesee_event_adapter ${catkin_EXPORTED_TARGETS})

add_executable(prophesee_device_info src/prophesee_device_info.cpp)
target_link_libraries(prophesee_device_info MetavisionSDK::driver)

add_executable(prophesee_dvs_driver src/prophesee_dvs_driver.cpp)
target_link_libraries(prophesee_dvs_driver ${catkin_LIBRARIES} MetavisionSDK::driver)
add_dependencies(prophesee_dvs_driver ${catkin_EXPORTED_TARGETS})

add_executable(prophesee_raw_info src/prophesee_raw_info.cpp)
target_link_libraries(prophesee_raw_info MetavisionSDK::driver)

add_executable(prophesee_raw_recorder src/prophesee_raw_recorder.cpp)
target_link_libraries(prophesee_raw_recorder MetavisionSDK::driver)

add_executable(prophesee_dual_raw_recorder src/prophesee_dual_raw_recorder.cpp)
target_link_libraries(prophesee_dual_raw_recorder MetavisionSDK::driver)

add_executable(prophesee_raw_publisher src/prophesee_raw_publisher.cpp)
target_link_libraries(prophesee_raw_publisher ${catkin_LIBRARIES} MetavisionSDK::driver)
add_dependencies(prophesee_raw_publisher ${catkin_EXPORTED_TARGETS})

add_executable(prophesee_raw_dvs_publisher src/prophesee_raw_dvs_publisher.cpp)
target_link_libraries(prophesee_raw_dvs_publisher ${catkin_LIBRARIES} MetavisionSDK::driver)
add_dependencies(prophesee_raw_dvs_publisher ${catkin_EXPORTED_TARGETS})

install(TARGETS
  camera_info_gate
  prophesee_event_adapter
  prophesee_device_info
  prophesee_dual_raw_recorder
  prophesee_dvs_driver
  prophesee_raw_info
  prophesee_raw_dvs_publisher
  prophesee_raw_publisher
  prophesee_raw_recorder
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY include/${PROJECT_NAME}/
  DESTINATION ${CATKIN_PACKAGE_INCLUDE_DESTINATION}
)
