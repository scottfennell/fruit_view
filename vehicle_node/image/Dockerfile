FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
	ca-certificates \
	curl \
	dosfstools \
	e2fsprogs \
	mount \
	openssh-client \
	parted \
	python3 \
	rsync \
	util-linux \
	xz-utils \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
