# Most Formal Stack

Utility for deploying docker images to Amazon ECS.


## How to docker

1a. If you're behind a proxy and using private dns servers, check
[http://stackoverflow.com/questions/25130536/dockerfile-docker-build-cant-download-packages-centos-yum-debian-ubuntu-ap](http://stackoverflow.com/questions/25130536/dockerfile-docker-build-cant-download-packages-centos-yum-debian-ubuntu-ap)

### Get a Container up and runnin

	$ eval "$(docker-machine env [machine name])" # make sure your env knows about the docker machine
	$ docker build [--no-cache] -t username/image .
	$ docker run -d -p 8000:8000 username/image
	$ docker ps # Verify that it's running
	$ echo $DOCKER_HOST # Get the IP