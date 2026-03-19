FROM lcr.loongnix.cn/library/golang:1.25

RUN apt-get update && apt-get install -y \
    bash \
    sed \
    wget \
    git \
    coreutils \
    gcc \
    libc6-dev \
    libseccomp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["/bin/bash"]
