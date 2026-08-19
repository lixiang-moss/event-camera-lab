ARG UBUNTU_VERSION=20.04

FROM ubuntu:${UBUNTU_VERSION} AS openeb-builder

ARG DEBIAN_FRONTEND=noninteractive
ARG OPENEB_VERSION=4.6.2
ARG OPENEB_COMMIT=53b3618935f90dcc0f64993ccbb79514384404b0
ARG OPENEB_BUILD_JOBS=4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    ffmpeg \
    git \
    hdf5-tools \
    libboost-all-dev \
    libcanberra-gtk-module \
    libglew-dev \
    libglfw3-dev \
    libhdf5-dev \
    libopencv-dev \
    libprotobuf-dev \
    libusb-1.0-0-dev \
    protobuf-compiler \
    software-properties-common \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${OPENEB_VERSION}" --recurse-submodules --shallow-submodules \
      https://github.com/prophesee-ai/openeb.git /opt/openeb \
    && test "$(git -C /opt/openeb rev-parse HEAD)" = "${OPENEB_COMMIT}" \
    && cmake -S /opt/openeb -B /opt/openeb/build \
      -DBUILD_TESTING=OFF \
      -DCOMPILE_PYTHON3_BINDINGS=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/metavision \
    && cmake --build /opt/openeb/build --target install -- -j"${OPENEB_BUILD_JOBS}"

RUN test "$(git -C /opt/openeb rev-parse HEAD)" = "${OPENEB_COMMIT}" \
    && { \
      printf 'openeb_version=%s\n' "${OPENEB_VERSION}"; \
      printf 'openeb_commit=%s\n' "$(git -C /opt/openeb rev-parse HEAD)"; \
    } > /opt/metavision/share/openeb-build-info.txt


FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=noetic
ARG OPENEB_VERSION=4.6.2
ARG OPENEB_COMMIT=53b3618935f90dcc0f64993ccbb79514384404b0

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV ROS_DISTRO=${ROS_DISTRO}
ENV ROS_WS=/workspace/ros_ws
ENV METAVISION_PREFIX=/opt/metavision
ENV OPENEB_VERSION=${OPENEB_VERSION}
ENV OPENEB_COMMIT=${OPENEB_COMMIT}
ENV PATH=/opt/metavision/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/metavision/lib
ENV CMAKE_PREFIX_PATH=/opt/metavision
ENV MV_HAL_PLUGIN_PATH=/opt/metavision/lib/metavision/hal/plugins
ENV HDF5_PLUGIN_PATH=/opt/metavision/lib/hdf5/plugin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release \
    && curl -sSL "https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc" | apt-key add - \
    && echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros1-latest.list \
    && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C8EC952E2A0E1FBDC5090F6A2C277A0A352154E5 \
    && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1D3782C07F873130548A7E822F2CC7DEE2CE4E6A \
    && echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu focal main" > /etc/apt/sources.list.d/ubuntu-toolchain-r-test.list \
    && echo "deb http://ppa.launchpad.net/inivation-ppa/inivation/ubuntu focal main" > /etc/apt/sources.list.d/inivation-ppa-inivation.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ffmpeg \
    git \
    hdf5-tools \
    libboost-all-dev \
    libcaer-dev \
    libcanberra-gtk-module \
    libglew-dev \
    libglfw3-dev \
    libhdf5-dev \
    libopencv-dev \
    libprotobuf-dev \
    libusb-1.0-0-dev \
    lz4 \
    protobuf-compiler \
    python3-catkin-tools \
    python3-coverage \
    python3-mock \
    python3-pil \
    python3-pip \
    python3-opencv \
    python3-rosdep \
    python3-vcstool \
    python3-yaml \
    ros-${ROS_DISTRO}-camera-calibration \
    ros-${ROS_DISTRO}-camera-info-manager \
    ros-${ROS_DISTRO}-cmake-modules \
    ros-${ROS_DISTRO}-cv-bridge \
    ros-${ROS_DISTRO}-dynamic-reconfigure \
    ros-${ROS_DISTRO}-image-transport \
    ros-${ROS_DISTRO}-image-view \
    ros-${ROS_DISTRO}-nodelet \
    ros-${ROS_DISTRO}-ros-base \
    ros-${ROS_DISTRO}-rosbag \
    ros-${ROS_DISTRO}-rqt-graph \
    ros-${ROS_DISTRO}-rqt-image-view \
    ros-${ROS_DISTRO}-rqt-reconfigure \
    ros-${ROS_DISTRO}-rviz \
    ros-${ROS_DISTRO}-sensor-msgs \
    ros-${ROS_DISTRO}-std-msgs \
    software-properties-common \
    sudo \
    usbutils \
    vim-tiny \
    && if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then rosdep init; fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=openeb-builder /opt/metavision /opt/metavision
COPY --from=openeb-builder /opt/openeb/licensing/LICENSE_OPEN /opt/metavision/share/licenses/openeb/LICENSE_OPEN
COPY --from=openeb-builder /opt/openeb/hal_psee_plugins/resources/rules/88-cyusb.rules /opt/metavision/share/udev/88-cyusb.rules

RUN useradd --create-home --shell /bin/bash --uid 1000 developer \
    && usermod -aG dialout,video,plugdev developer \
    && mkdir -p /workspace \
    && chown -R developer:developer /workspace \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER developer
WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
