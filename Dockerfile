FROM ubuntu:24.04 AS core

# Core utilities
RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        zip unzip wget bzip2 curl git jq yq \
        libffi-dev libncurses5-dev libsqlite3-dev libssl-dev libicu-dev \
        python-is-python3 python3-venv python3-pip \
        ca-certificates openssh-client build-essential docker.io gnupg2

# Set up SSH for git and bitbucket
RUN mkdir -p ~/.ssh \
    && touch ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa,ed25519,ecdsa -H github.com >> ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa,ed25519,ecdsa -H bitbucket.org >> ~/.ssh/known_hosts \
    && chmod 600 ~/.ssh/known_hosts

FROM core AS tools

RUN python -m venv env \
    && . env/bin/activate \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --upgrade PyYAML setuptools awscli wheel \
    && pip install --no-cache-dir "launch-cli" \
    && launch --version

# repo
RUN curl https://storage.googleapis.com/git-repo-downloads/repo -o /usr/bin/repo \
    && chmod a+rx /usr/bin/repo

# Cleanup
RUN rm -fr /tmp/* /var/tmp/*

FROM tools AS lcaf

ARG GIT_USERNAME="nobody" \
    GIT_EMAIL_DOMAIN="nttdata.com" \
    REPO_TOOL="https://github.com/launchbynttdata/git-repo.git"

# Environment variables
ENV TOOLS_DIR="/usr/local/opt" \
    IS_PIPELINE=true

# Git config defaults to allow for basic testing -- override these when consuming this image.
RUN git config --global user.name nobody && git config --global user.email nobody@nowhere.com

# Create work directory
RUN mkdir -p ${TOOLS_DIR}/launch-build-agent
WORKDIR ${TOOLS_DIR}/launch-build-agent/

# Install asdf
# TODO: migrate to mise.
COPY ./.tool-versions ${TOOLS_DIR}/launch-build-agent/.tool-versions
COPY ./scripts/asdf-setup.sh ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh
RUN ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh
ENV PATH="$PATH:/root/.asdf/bin:/root/.asdf/shims"

# Install launch's modified git-repo
RUN git clone "${REPO_TOOL}" "${TOOLS_DIR}/git-repo" \
    && cd "${TOOLS_DIR}/git-repo" \
    && export PATH="$PATH:${TOOLS_DIR}/git-repo" \
    && chmod +x "repo"
