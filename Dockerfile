FROM ubuntu:24.04 AS core

RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        wget gnupg2

# Source for headless Chrome installation
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list

# Core utilities
RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        zip unzip bzip2 curl git jq yq \
        libffi-dev libncurses5-dev libsqlite3-dev libssl-dev libicu-dev \
        liblzma-dev libbz2-dev libreadline-dev \
        python-is-python3 python3-venv python3-pip \
        ca-certificates openssh-client build-essential docker.io \
    && apt-get install -y google-chrome-stable --no-install-recommends --fix-missing \
    && rm -rf /var/lib/apt/lists/*

# Create Launch User
RUN groupadd -r launch \
    && useradd -r -g launch -G audio,video launch \
    && mkdir -p /home/launch \
    && chown -R launch:launch /home/launch

USER launch

WORKDIR /home/launch

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
ENV TOOLS_DIR="/home/launch/tools" \
    IS_PIPELINE=true

# Create work directory
RUN mkdir -p ${TOOLS_DIR}/launch-build-agent
WORKDIR ${TOOLS_DIR}/launch-build-agent/

# Install asdf
# TODO: migrate to mise.
COPY ./.tool-versions ${TOOLS_DIR}/launch-build-agent/.tool-versions
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
RUN cd /usr/local/opt/launch-build-agent \
    && make git-config \
    && make configure \ 
    && rm -rf $HOME/.gitconfig

# Git config defaults to allow for basic testing -- override these when consuming this image.
RUN git config --global user.name nobody && git config --global user.email nobody@nowhere.com
