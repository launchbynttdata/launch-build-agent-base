FROM ubuntu:24.04 AS core

RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        wget gnupg2

# Core utilities
RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        zip unzip bzip2 curl git jq yq \
        libffi-dev libncurses5-dev libsqlite3-dev libssl-dev libicu-dev \
        liblzma-dev libbz2-dev libreadline-dev \
        python-is-python3 python3-venv python3-pip \
        ca-certificates openssh-client build-essential

# Install Docker
COPY ./scripts/install-docker.sh ${TOOLS_DIR}/launch-build-agent/install-docker.sh
RUN ${TOOLS_DIR}/launch-build-agent/install-docker.sh

# Install AWS CLI version 2 for the platform
ARG TARGETARCH
COPY ./scripts/install-awscliv2-${TARGETARCH}.sh ${TOOLS_DIR}/launch-build-agent/install-awscliv2-${TARGETARCH}.sh
RUN ${TOOLS_DIR}/launch-build-agent/install-awscliv2-${TARGETARCH}.sh

# Install Google Chrome for the platform. Needed for Angular tests.
COPY ./scripts/install-chrome-${TARGETARCH}.sh ${TOOLS_DIR}/launch-build-agent/install-chrome-${TARGETARCH}.sh
RUN ${TOOLS_DIR}/launch-build-agent/install-chrome-${TARGETARCH}.sh

# Cleanup
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* awscliv2.zip ./aws

# Create home folder for Launch user
RUN mkdir -p /home/launch

# Put repo somewhere accessible
RUN curl https://storage.googleapis.com/git-repo-downloads/repo -o /home/launch/repo \
    && chmod a+rx /home/launch/repo

# Create Launch User
RUN groupadd -r launch \
    && useradd -r -g launch -G audio,video launch \
    && chown -R launch:launch /home/launch

USER launch

ENV PATH="$PATH:/home/launch"

WORKDIR /home/launch

# Set up SSH for git and bitbucket
RUN mkdir -p ~/.ssh \
    && touch ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa,ed25519,ecdsa -H github.com >> ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa,ed25519,ecdsa -H bitbucket.org >> ~/.ssh/known_hosts \
    && chmod 600 ~/.ssh/known_hosts

FROM core AS tools

ENV PATH="$PATH:/home/launch"

RUN pip install --no-cache-dir --upgrade --break-system-packages pip \
    && pip install --no-cache-dir --break-system-packages --upgrade PyYAML setuptools wheel
    # && pip install --no-cache-dir --break-system-packages "launch-cli"

# DELETE ME - launch-cli dev branch
RUN git clone https://github.com/launchbynttdata/launch-cli.git --branch "patch/reworking-git-token" \
    && cd launch-cli \
    && python -m pip install -e '.[dev]' --break-system-packages


ENV PATH="$PATH:/home/launch/.local/bin"

# Cleanup
RUN rm -fr /tmp/* /var/tmp/*

FROM tools AS lcaf

ARG GIT_USERNAME="nobody" \
    GIT_EMAIL_DOMAIN="nttdata.com" \
    REPO_TOOL="https://github.com/launchbynttdata/git-repo.git"

# Environment variables
ENV TOOLS_DIR="/home/launch/tools" \
    IS_PIPELINE=true

# Create work directory
RUN mkdir -p ${TOOLS_DIR}/launch-build-agent
WORKDIR ${TOOLS_DIR}/launch-build-agent/

# Install asdf
# TODO: migrate to mise.
COPY ./.tool-versions ${TOOLS_DIR}/launch-build-agent/.tool-versions
COPY ./.tool-versions /home/launch/.tool-versions
COPY ./scripts/asdf-setup.sh ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh
RUN ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh
ENV PATH="$PATH:/home/launch/.asdf/bin:/home/launch/.asdf/shims"

# Install launch's modified git-repo
RUN git clone "${REPO_TOOL}" "${TOOLS_DIR}/git-repo" \
    && cd "${TOOLS_DIR}/git-repo" \
    && export PATH="$PATH:${TOOLS_DIR}/git-repo" \
    && chmod +x "repo"

# Run make configure to install platform tools from .tool-versions
COPY "./Makefile" "${TOOLS_DIR}/launch-build-agent/Makefile"
ENV BUILD_ACTIONS_DIR="${TOOLS_DIR}/launch-build-agent/components/build-actions" \
    PATH="$PATH:${BUILD_ACTIONS_DIR}" \
    JOB_NAME="${GIT_USERNAME}" \
    JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}"
RUN cd ${TOOLS_DIR}/launch-build-agent \
    && make git-config \
    && make configure \
    && rm -rf $HOME/.gitconfig

# Copy the launch tools/packages to the root user's home directory
USER root
RUN cp -r /home/launch/* /root/ && \
    cp -r /home/launch/.[!.]* /root/

USER launch

# Git config defaults to allow for basic testing -- override these when consuming this image.
RUN git config --global user.name nobody && git config --global user.email nobody@nowhere.com
