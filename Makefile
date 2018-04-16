all:
	echo Got here.

docker-build:
	docker build -t pwmgr:dev .

docker-test: docker-build
	docker run --rm -t pwmgr:dev prove -eperl6 -r xt/
