all:
	echo Got here.

docker-build:
	docker build -t pwmgr .

docker-test:
	prove -e'docker run --rm -t -v ${PWD}:/root/pwmgr pwmgr perl6 -Ilib' t/
