FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget ccache && \
    rm -rf /var/lib/apt/lists/*

# GNU host tools such as tar require this when building as root in the container.
ENV FORCE_UNSAFE_CONFIGURE=1

WORKDIR /deploy
ENTRYPOINT ["/deploy/build.sh"]
