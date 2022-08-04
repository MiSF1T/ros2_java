ARG FROM_IMAGE=ros:galactic
ARG OVERLAY_WS=/opt/overlay_ws

# multi-stage for caching
FROM $FROM_IMAGE AS cacher

# clone overlay source
ARG OVERLAY_WS
ARG REPOS_FILE=ros2_java_desktop.repos
WORKDIR $OVERLAY_WS/src
COPY ./$REPOS_FILE ../
RUN vcs import ./ < ../$REPOS_FILE
COPY ./ ./ros2-java/ros2_java

# copy manifests for caching
WORKDIR /opt
RUN mkdir -p /tmp/opt; \
    find ./ -name "package.xml" | \
        xargs cp --parents -t /tmp/opt; \
    find ./ -name "COLCON_IGNORE" | \
        xargs cp --parents -t /tmp/opt || true


# multi-stage for developing
FROM $FROM_IMAGE AS developer
ARG DEBIAN_FRONTEND=noninteractive

# install system dependencies
RUN apt-get update && apt-get install -q -y \
        curl \
        default-jdk \
        gradle \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# install tool dependencies
RUN pip install \
        git+https://github.com/colcon/colcon-gradle \
        git+https://github.com/colcon/colcon-ros-gradle

# install overlay dependencies
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS
COPY --from=cacher /tmp/$OVERLAY_WS ./
RUN . /opt/ros/$ROS_DISTRO/setup.sh; \
    apt-get update && rosdep install -y \
      --from-paths src \
      --ignore-src \
      --skip-keys " \
        ament_tools \
        " \
    && rm -rf /var/lib/apt/lists/*


# multi-stage for building
FROM developer AS builder

# build overlay source
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS
COPY --from=cacher $OVERLAY_WS ./
ARG OVERLAY_MIXINS="release"
RUN . /opt/ros/$ROS_DISTRO/setup.sh; \
    colcon build \
      --symlink-install \
      --mixin $OVERLAY_MIXINS

# source overlay from entrypoint
ENV OVERLAY_WS $OVERLAY_WS
RUN sed --in-place \
      's|^source .*|source "$OVERLAY_WS/install/setup.bash"|' \
      /ros_entrypoint.sh


# multi-stage for testing
FROM builder AS tester

# test overlay build
RUN . install/setup.sh; \
    colcon test; \
    colcon test-result
