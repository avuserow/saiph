all:
	echo Got here.

docker-build:
	docker build -t saiph:dev .

docker-test: docker-build
	prove -v -e'docker run --rm -t saiph:dev raku' -r xt/
