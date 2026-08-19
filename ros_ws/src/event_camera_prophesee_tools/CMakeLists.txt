cmake_minimum_required(VERSION 3.0.2)
project(event_camera_prophesee_tools)

add_compile_options(-std=c++14 -O3)

find_package(catkin REQUIRED COMPONENTS
  camera_info_manager
  dvs_msgs
  prophesee_event_msgs
  roscpp
  sensor_msgs
)
find_package(MetavisionSDK COMPONENTS driver REQUIRED)

catkin_package(
  CATKIN_DEPENDS camera_info_manager dvs_msgs prophesee_event_msgs roscpp sensor_msgs
)

include_directories(${catkin_INCLUDE_DIRS})

add_executable(prophesee_event_adapter src/prophesee_event_adapter.cpp)
target_link_libraries(prophesee_event_adapter ${catkin_LIBRARIES})
add_dependencies(prophesee_event_adapter ${catkin_EXPORTED_TARGETS})

add_executable(prophesee_device_info src/prophesee_device_info.cpp)
target_link_libraries(prophesee_device_info MetavisionSDK::driver)

add_executable(prophesee_raw_info src/prophesee_raw_info.cpp)
target_link_libraries(prophesee_raw_info MetavisionSDK::driver)

add_executable(prophesee_raw_recorder src/prophesee_raw_recorder.cpp)
target_link_libraries(prophesee_raw_recorder MetavisionSDK::driver)

add_executable(prophesee_raw_publisher src/prophesee_raw_publisher.cpp)
target_link_libraries(prophesee_raw_publisher ${catkin_LIBRARIES} MetavisionSDK::driver)
add_dependencies(prophesee_raw_publisher ${catkin_EXPORTED_TARGETS})

install(TARGETS
  prophesee_event_adapter
  prophesee_device_info
  prophesee_raw_info
  prophesee_raw_publisher
  prophesee_raw_recorder
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)
