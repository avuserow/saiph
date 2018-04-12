all:
	echo Got here.

docker-test:
	prove -e'sudo docker run --rm -t pwmgr perl6' t/
