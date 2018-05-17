all:
	echo Got here.

docker-build:
	docker build -t pwmgr:dev .

docker-test: docker-build
	prove -v -e'docker run --rm -t pwmgr:dev perl6' -r xt/
