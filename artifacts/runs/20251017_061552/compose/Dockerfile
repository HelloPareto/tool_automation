#############################################################
# BASE IMAGE: Common Foundation for All Tools
#############################################################
# This image provides all common system-level dependencies
# that tools will need at runtime. Tools build on top of this.
#############################################################

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

#############################################################
# STEP 1: Create model user FIRST (before any packages)
# This ensures consistent UID/GID across all tools
#############################################################
RUN groupadd -g 1000 model && \
    useradd -m -u 1000 -g 1000 model && \
    gpasswd -d model root || true

#############################################################
# STEP 2: Locale and Terminal Support
#############################################################
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TERM=xterm-256color

#############################################################
# STEP 3: Install All Common Runtime Dependencies
#############################################################
RUN apt-get update && apt-get install -y --no-install-recommends \
    #############################################################
    ## Python 3.11 (available in Debian 12 by default)
    #############################################################
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    #############################################################
    ## Build Tools
    #############################################################
    build-essential \
    gcc \
    g++ \
    make \
    #############################################################
    ## Locale and Terminal Support
    #############################################################
    locales \
    locales-all \
    ncurses-term \
    #############################################################
    ## Scientific Computing Dependencies
    #############################################################
    gfortran \
    libblas-dev \
    liblapack-dev \
    libatlas-base-dev \
    libffi-dev \
    libbz2-dev \
    liblzma-dev \
    libzstd-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libfreetype6-dev \
    libpng-dev \
    pkg-config \
    #############################################################
    ## Development Tools
    #############################################################
    wget \
    curl \
    git \
    sudo \
    ca-certificates \
    #############################################################
    ## PostgreSQL Development Libraries (for psycopg2-binary)
    #############################################################
    libpq-dev \
    #############################################################
    ## UI Packages for Computer Use
    #############################################################
    xvfb \
    xterm \
    xdotool \
    scrot \
    imagemagick \
    mutter \
    x11vnc \
    xclip \
    tint2 \
    x11-utils \
    #############################################################
    ## Init System Support
    #############################################################
    lsb-base \
    #############################################################
    ## Firefox Dependencies
    #############################################################
    libpci3 \
    #############################################################
    ## Networking
    #############################################################
    net-tools \
    netcat-openbsd \
    #############################################################
    ## SQLite Database
    #############################################################
    sqlite3 \
    #############################################################
    ## Firefox ESR (Debian includes this by default)
    #############################################################
    firefox-esr \
    #############################################################
    ## LibreOffice Suite (Desktop application)
    #############################################################
    openjdk-17-jre-headless \
    libreoffice \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-math \
    libreoffice-base \
    libreoffice-java-common \
    libreoffice-script-provider-python \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

#############################################################
# STEP 4: Python Version Management and pip/uv
# Debian 12 comes with Python 3.11 by default
#############################################################
RUN python3 -m pip install --upgrade pip --break-system-packages && \
    python3 -m pip install uv --break-system-packages

#############################################################
# STEP 5: Data Science Python Libraries
# These are common to the environment and used by multiple tools
#############################################################
RUN python3 -m pip install --break-system-packages \
    numpy \
    scipy \
    pandas \
    matplotlib \
    seaborn \
    scikit-learn

#############################################################
# STEP 6: Configure XTerm with Black Background
#############################################################
RUN echo 'XTerm*background: black' >> /etc/X11/app-defaults/XTerm && \
    echo 'XTerm*foreground: white' >> /etc/X11/app-defaults/XTerm && \
    echo 'XTerm*vt100.translations: #override \\' >> /etc/X11/app-defaults/XTerm && \
    echo 'Shift Ctrl <Key> C: copy-selection(CLIPBOARD) \\n\\' >> /etc/X11/app-defaults/XTerm && \
    echo 'Shift Ctrl <Key> V: insert-selection(CLIPBOARD)' >> /etc/X11/app-defaults/XTerm

#############################################################
# This base image is now ready to be used by tool builders
#############################################################
RUN mkdir -p /workspace && chmod 755 /workspace
COPY shared_setup.sh /workspace/shared_setup.sh
COPY tools/gnucash/tool_setup.sh /workspace/tools/gnucash/tool_setup.sh
COPY tools/openemr/tool_setup.sh /workspace/tools/openemr/tool_setup.sh
COPY run_all.sh /workspace/run_all.sh
RUN chmod +x /workspace/run_all.sh /workspace/shared_setup.sh || true
