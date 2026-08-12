FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=noetic

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV ROS_DISTRO=${ROS_DISTRO}
ENV ROS_WS=/workspace/ros_ws

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
    git \
    libcaer-dev \
    python3-catkin-tools \
    python3-pip \
    python3-rosdep \
    python3-vcstool \
    ros-${ROS_DISTRO}-camera-info-manager \
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
    usbutils \
    vim-tiny \
    && if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then rosdep init; fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash --uid 1000 developer \
    && usermod -aG dialout,video,plugdev developer \
    && mkdir -p /workspace \
    && chown -R developer:developer /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
    lz4 \
    python3-coverage \
    python3-mock \
    python3-pil \
    sudo \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER developer
WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
