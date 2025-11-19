#!/usr/bin/env bash
# this script builds a ROS2 distribution from source
# ROS_DISTRO, ROS_ROOT, ROS_PKG environment variables should be set

echo "ROS2 builder => ROS_DISTRO=$ROS_DISTRO ROS_PKG=$ROS_PKG ROS_ROOT=$ROS_ROOT"

set -e
#set -x

# add the ROS deb repo to the apt sources list
apt-get update
apt-get install -y --no-install-recommends \
		curl \
		wget \
		gnupg2 \
		lsb-release \
		ca-certificates

curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null
apt-get update

# install development packages
apt-get install -y --no-install-recommends \
		build-essential \
		cmake \
		git \
		libbullet-dev \
		libpython3-dev \
		python3-colcon-common-extensions \
		python3-flake8 \
		python3-pip \
		python3-numpy \
		python3-pytest-cov \
		python3-rosdep \
		python3-setuptools \
		python3-vcstool \
		python3-rosinstall-generator \
		libasio-dev \
		libtinyxml2-dev \
		libcunit1-dev

# install some pip packages needed for testing
pip3 install --upgrade --no-cache-dir \
		argcomplete \
		flake8-blind-except \
		flake8-builtins \
		flake8-class-newline \
		flake8-comprehensions \
		flake8-deprecated \
		flake8-docstrings \
		flake8-import-order \
		flake8-quotes \
		pytest-repeat \
		pytest-rerunfailures \
		pytest

# upgrade cmake - https://stackoverflow.com/a/56690743
# this is needed to build some of the ROS2 packages
# Install CMake from official Kitware binary for ARM64 instead of broken pip version
# Pin to 3.31.9 to avoid CMake 4.0+ compatibility issues with osrf_testing_tools_cpp
# https://github.com/osrf/osrf_testing_tools_cpp/issues/91
wget -q https://github.com/Kitware/CMake/releases/download/v3.31.9/cmake-3.31.9-linux-aarch64.sh
chmod +x cmake-3.31.9-linux-aarch64.sh
./cmake-3.31.9-linux-aarch64.sh --skip-license --prefix=/usr/local
rm cmake-3.31.9-linux-aarch64.sh
cmake --version
which cmake

# remove other versions of Python3
# workaround for 'Could NOT find Python3 (missing: Python3_NumPy_INCLUDE_DIRS Development'
apt purge -y python3.9 libpython3.9* || echo "python3.9 not found, skipping removal"
ls -ll /usr/bin/python*
    
# create build directory in /tmp (isolated from final install location)
mkdir -p /tmp/ros_build/src
cd /tmp/ros_build

# download ROS sources
# https://answers.ros.org/question/325245/minimal-ros2-installation/?answer=325249#post-id-325249
rosinstall_generator --deps --rosdistro ${ROS_DISTRO} ${ROS_PKG} \
	launch_xml \
	launch_yaml \
	launch_testing \
	launch_testing_ament_cmake \
	demo_nodes_cpp \
	demo_nodes_py \
	example_interfaces \
	camera_calibration_parsers \
	camera_info_manager \
	cv_bridge \
	v4l2_camera \
	vision_opencv \
	vision_msgs \
	image_geometry \
	image_pipeline \
	image_transport \
	compressed_image_transport \
	compressed_depth_image_transport \
> ros2.${ROS_DISTRO}.${ROS_PKG}.rosinstall
cat ros2.${ROS_DISTRO}.${ROS_PKG}.rosinstall
vcs import src < ros2.${ROS_DISTRO}.${ROS_PKG}.rosinstall
    
# https://github.com/dusty-nv/jetson-containers/issues/181
rm -r /tmp/ros_build/src/ament_cmake
git -C /tmp/ros_build/src/ clone https://github.com/ament/ament_cmake -b ${ROS_DISTRO}

# skip installation of some conflicting packages
SKIP_KEYS="libopencv-dev libopencv-contrib-dev libopencv-imgproc-dev python-opencv python3-opencv"

# patches for building Humble on 18.04
if [ "$ROS_DISTRO" = "humble" ] || [ "$ROS_DISTRO" = "iron" ] && [ $(lsb_release --codename --short) = "bionic" ]; then
	# rti_connext_dds_cmake_module: No definition of [rti-connext-dds-6.0.1] for OS version [bionic]
	SKIP_KEYS="$SKIP_KEYS rti-connext-dds-6.0.1 ignition-cmake2 ignition-math6"

	# the default gcc-7 is too old to build humble
	apt-get install -y --no-install-recommends gcc-8 g++-8
	export CC="/usr/bin/gcc-8"
	export CXX="/usr/bin/g++-8"
	echo "CC=$CC CXX=$CXX"

	# upgrade pybind11
	apt-get purge -y pybind11-dev
	pip3 install --upgrade --no-cache-dir pybind11-global
   
	# https://github.com/dusty-nv/jetson-containers/issues/160#issuecomment-1429572145
	git -C /tmp clone -b yaml-cpp-0.6.0 https://github.com/jbeder/yaml-cpp.git
	cmake -S /tmp/yaml-cpp -B /tmp/yaml-cpp/BUILD -DBUILD_SHARED_LIBS=ON
	cmake --build /tmp/yaml-cpp/BUILD --parallel $(nproc --ignore=1)
	cmake --install /tmp/yaml-cpp/BUILD
	rm -rf /tmp/yaml-cpp
fi
    
echo "--skip-keys $SKIP_KEYS"
    
# install dependencies using rosdep
rosdep init
rosdep update
rosdep install -y \
	--ignore-src \
	--from-paths src \
	--rosdistro ${ROS_DISTRO} \
	--skip-keys "$SKIP_KEYS"

# build it all - for verbose, see https://answers.ros.org/question/363112/how-to-see-compiler-invocation-in-colcon-build
# Install directly to ${ROS_ROOT} (e.g., /opt/ros/humble) instead of /opt/ros/humble/install
colcon build \
	--merge-install \
	--install-base ${ROS_ROOT} \
	--cmake-args -DCMAKE_BUILD_TYPE=Release

# remove entire build directory
cd /
rm -rf /tmp/ros_build
    
# cleanup apt   
rm -rf /var/lib/apt/lists/*
apt-get clean
