FROM ubuntu:24.04 AS core
ARG TARGETARCH

# Install necessary packages
RUN set -ex \
    && apt-get update \
    && apt-get install -y \
        wget gnupg2 zip unzip bzip2 curl git jq yq \
        libffi-dev libncurses5-dev libsqlite3-dev libssl-dev libicu-dev \
        liblzma-dev libbz2-dev libreadline-dev \
        python-is-python3 python3-venv python3-pip \
        ca-certificates openssh-client build-essential

# Copy install scripts to the container
ENV TOOLS_DIR="/home/launch/tools"
COPY ./scripts/install-docker.sh ${TOOLS_DIR}/launch-build-agent/install-docker.sh
COPY ./scripts/install-chrome-${TARGETARCH}.sh ${TOOLS_DIR}/launch-build-agent/install-chrome-${TARGETARCH}.sh

# Install Docker, Chrome, and set up the launch user
RUN ${TOOLS_DIR}/launch-build-agent/install-docker.sh \
    && ${TOOLS_DIR}/launch-build-agent/install-chrome-${TARGETARCH}.sh \
    && apt-get autoremove -y \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && mkdir -p /home/launch \
    && curl https://storage.googleapis.com/git-repo-downloads/repo -o /home/launch/repo \
    && chmod a+rx /home/launch/repo \
    && groupadd -r launch \
    && useradd -r -g launch -G audio,video launch \
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

RUN pip install --no-cache-dir --upgrade --break-system-packages pip \
    && pip install --no-cache-dir --break-system-packages --upgrade PyYAML setuptools wheel

RUN git clone https://github.com/launchbynttdata/launch-cli.git ~/launch-cli
RUN cd ~/launch-cli
RUN git checkout bug/pipeline-multi
RUN pip install . --break-system-packages

FROM tools AS lcaf

ARG GIT_USERNAME="nobody" \
    GIT_EMAIL_DOMAIN="nttdata.com" \
    REPO_TOOL="https://github.com/launchbynttdata/git-repo.git"

# Environment variables
ENV TOOLS_DIR="/home/launch/tools" \
    IS_PIPELINE=true \
    BUILD_ACTIONS_DIR="${TOOLS_DIR}/launch-build-agent/components/build-actions" \
    JOB_NAME="${GIT_USERNAME}" \
    JOB_EMAIL="${GIT_USERNAME}@${GIT_EMAIL_DOMAIN}" \
    PATH="$PATH:/home/launch:/home/launch/.asdf/bin:/home/launch/.asdf/shims:/home/launch/.local/bin:${TOOLS_DIR}/git-repo:${BUILD_ACTIONS_DIR}"

# Create work directory
RUN mkdir -p ${TOOLS_DIR}/launch-build-agent
WORKDIR ${TOOLS_DIR}/launch-build-agent/

# Copy the necessary files to the container
COPY ./.tool-versions ${TOOLS_DIR}/launch-build-agent/.tool-versions
COPY ./.tool-versions /home/launch/.tool-versions
COPY ./scripts/asdf-setup.sh ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh
COPY "./Makefile" "${TOOLS_DIR}/launch-build-agent/Makefile"

# Install asdf, git-repo, and run make commands
RUN ${TOOLS_DIR}/launch-build-agent/asdf-setup.sh \
    && git clone "${REPO_TOOL}" "${TOOLS_DIR}/git-repo" \
    && cd "${TOOLS_DIR}/git-repo" \
    && chmod +x "repo" \
    && cd ${TOOLS_DIR}/launch-build-agent \
    && make git-config \
    && make configure \
    && rm -rf $HOME/.gitconfig

# Copy the launch tools/packages to the root user's home directory
USER root
RUN cp -r /home/launch/* /root/ \
    && cp -r /home/launch/.[!.]* /root/ \
    && git config --system user.name nobody && git config --system user.email nobody@nttdata.com

USER launch

# Clean up
RUN rm -fr /tmp/* /var/tmp/* \
    && rm -rf /usr/share/dotnet \
    && rm -rf /opt/ghc \
    && rm -rf "/usr/local/share/boost" \
    && rm -rf "$AGENT_TOOLSDIRECTORY"
