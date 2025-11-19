#!/bin/bash
#set -e

function ros_source_env() 
{
	if [ -f "$1" ]; then
		echo "sourcing   $1"
		source "$1"
	else
		echo "notfound   $1"
	fi	
}

if [[ "$ROS_DISTRO" == "melodic" || "$ROS_DISTRO" == "noetic" ]]; then
	ros_source_env "/opt/ros/$ROS_DISTRO/setup.bash"
else
	# ROS 2: Source from ROS_ROOT (e.g., /opt/ros/humble/setup.bash)
	ros_source_env "$ROS_ROOT/setup.bash"
fi

echo "ROS_DISTRO $ROS_DISTRO"
echo "ROS_ROOT   $ROS_ROOT"

exec "$@"